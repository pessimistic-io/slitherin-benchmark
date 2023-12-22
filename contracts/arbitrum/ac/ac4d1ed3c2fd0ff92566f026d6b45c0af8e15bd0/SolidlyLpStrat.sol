// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC20.sol";
import "./SafeERC20.sol";

import "./GasFeeThrottler.sol";
import "./UniSwapRoutes.sol";
import "./Stoppable.sol";
import "./ISolidlyRouter.sol";
import "./ISolidlyPair.sol";
import "./IGauge.sol";
import "./Pausable.sol";
import "./FeeUtils.sol";
import "./SolidlyRoutes.sol";

contract SolidlyLpStrat is FeeUtils, SolidlyRoutes, GasFeeThrottler, Stoppable, Pausable {
    using SafeERC20 for IERC20;

    // Tokens used
    address public feeToken; //eg WETH -  The token dev fees are received in
    address public rewardToken; //eg RAM - The token that is rewarded for providing liquidity
    address public wantToken; //LP Token - The token representing your liquidity in the farm
    address public lp0Token; //eg WETH - The first token in the LP pair
    address public lp1Token; //eg ARB - The second token in the LP pair
    address public inputToken; //eg WETH || USDC - The token used for single deposits

    // Third party contracts
    address public gauge; //0x69a3de5f13677fd8d7aaf350a6c65de50e970262
    address public vault;
    address[] public rewards; // reward tokens

    uint256 constant DIVISOR = 1 ether;
    // is it a stable or volatile pool
    bool public isStable;
    bool public harvestOnDeposit;
    uint256 public lastPoolDepositTime;
    uint256 public lastHarvest;
    uint256 public tokenId;

    // Routes
    ISolidlyRouter.Routes[] public rewardTokenToFeeTokenRoute;
    ISolidlyRouter.Routes[] public rewardTokenToLp0TokenRoute;
    ISolidlyRouter.Routes[] public rewardTokenToLp1TokenRoute;
    ISolidlyRouter.Routes[] public inputTokenToLp0TokenRoute;
    ISolidlyRouter.Routes[] public inputTokenToLp1TokenRoute;
    ISolidlyRouter.Routes[] public lp0ToInputTokenRoute;
    ISolidlyRouter.Routes[] public lp1ToInputTokenRoute;

    event StratHarvest(address indexed harvester, uint256 wantTokenHarvested, uint256 tvl);
    event Deposit(uint256 tvl);
    event PendingDeposit(uint256 totalPending);
    event Withdraw(uint256 tvl);
    event ChargedFees(uint256 fees, uint256 amount);
    event CollectRewards(uint256 rewards);

    struct TokenRoutes {
        ISolidlyRouter.Routes[] rewardTokenToFeeTokenRoute;
        ISolidlyRouter.Routes[] rewardTokenToLp0TokenRoute;
        ISolidlyRouter.Routes[] rewardTokenToLp1TokenRoute;
        ISolidlyRouter.Routes[] inputTokenToLp0TokenRoute;
        ISolidlyRouter.Routes[] inputTokenToLp1TokenRoute;
        ISolidlyRouter.Routes[] lp0ToInputTokenRoute;
        ISolidlyRouter.Routes[] lp1ToInputTokenRoute;
    }

    constructor (
        address _vault,
        address _want,
        address _inputToken,
        address _gauge, // stakes LP
        address _router, // swaps the tokens
        uint256 _tokenId,
        TokenRoutes memory _routes
    ) SolidlyRoutes(_router) {
        vault = _vault;
        wantToken = _want;
        gauge = _gauge;
        router = _router;
        devFeeAddress = _msgSender();
        tokenId = _tokenId;

        // check if LP is stable or not
        // stable (correlated) vaults use the uniswapV2 model for LP
        // volatile vaults use the solidly model for LP
        isStable = ISolidlyPair(wantToken).stable();

        for (uint i; i < _routes.rewardTokenToFeeTokenRoute.length; ++i) {
            rewardTokenToFeeTokenRoute.push(_routes.rewardTokenToFeeTokenRoute[i]);
        }

        for (uint i; i < _routes.rewardTokenToLp0TokenRoute.length; ++i) {
            rewardTokenToLp0TokenRoute.push(_routes.rewardTokenToLp0TokenRoute[i]);
        }

        for (uint i; i < _routes.rewardTokenToLp1TokenRoute.length; ++i) {
            rewardTokenToLp1TokenRoute.push(_routes.rewardTokenToLp1TokenRoute[i]);
        }

        for (uint i; i < _routes.inputTokenToLp0TokenRoute.length; ++i) {
            inputTokenToLp0TokenRoute.push(_routes.inputTokenToLp0TokenRoute[i]);
        }

        for (uint i; i < _routes.inputTokenToLp1TokenRoute.length; ++i) {
            inputTokenToLp1TokenRoute.push(_routes.inputTokenToLp1TokenRoute[i]);
        }

        for (uint i; i < _routes.lp0ToInputTokenRoute.length; ++i) {
            lp0ToInputTokenRoute.push(_routes.lp0ToInputTokenRoute[i]);
        }

        for (uint i; i < _routes.lp1ToInputTokenRoute.length; ++i) {
            lp1ToInputTokenRoute.push(_routes.lp1ToInputTokenRoute[i]);
        }

        rewardToken = rewardTokenToFeeTokenRoute[0].from;
        inputToken = _inputToken;
        feeToken = rewardTokenToFeeTokenRoute[rewardTokenToFeeTokenRoute.length - 1].to;
        lp0Token = rewardTokenToLp0TokenRoute[rewardTokenToLp0TokenRoute.length - 1].to;
        lp1Token = rewardTokenToLp1TokenRoute[rewardTokenToLp1TokenRoute.length - 1].to;
        rewards.push(rewardToken);
        _giveAllowances();
    }

    modifier onlyVault() {
        require(vault == _msgSender(), "OnlyVault: caller is not the vault");
        _;
    }

    function depositWant() public whenNotPaused whenNotStopped {
        uint256 wantBalance = balanceOfWant();
        if (wantBalance > 0) {
            IGauge(gauge).deposit(wantBalance, tokenId);
            emit Deposit(wantBalance);
        }
    }

    // puts the funds to work
    // single token deposit
    function deposit() public whenNotPaused whenNotStopped {
        uint256 inputTokenBalance = IERC20(inputToken).balanceOf(address(this));
        if (inputTokenBalance > 0) {
            addLiquidityFromSingleToken(inputToken, inputTokenToLp0TokenRoute, inputTokenToLp1TokenRoute);
            depositWant();
        }
    }

    // deposit lp tokens simultaneously
    function depositLpTokens() public whenNotPaused whenNotStopped {
        (uint256 lp0Bal, uint256 lp1Bal) = lpTokenBalances();
        require(lp0Bal > 0, '!lp0Bal');
        require(lp1Bal > 0, '!lp1Bal');
        // TODO, do we to get a quote for this?
        ISolidlyRouter(router).addLiquidity(lp0Token, lp1Token, isStable, lp0Bal, lp1Bal, 1, 1, address(this), block.timestamp);
        depositWant();
    }

    function startWithdraw(uint256 amount) internal returns (uint256, uint256, uint256) {
        uint256 wantBal = IERC20(wantToken).balanceOf(address(this));
        uint256 lp0BalBefore = IERC20(lp0Token).balanceOf(address(this));
        uint256 lp1BalBefore = IERC20(lp1Token).balanceOf(address(this));

        if (wantBal < amount) {
            IGauge(gauge).withdraw(amount - wantBal);
            wantBal = IERC20(wantToken).balanceOf(address(this));
        }

        if (wantBal > amount) {
            wantBal = amount;
        }

        removeLiquidity(lp0Token, lp1Token, isStable, amount, 0, 0, 0);
        uint256 lp0BalAfter = IERC20(lp0Token).balanceOf(address(this));
        uint256 lp1BalAfter = IERC20(lp1Token).balanceOf(address(this));

        // Don't distribute any tokens that were sent to the contract by accident
        uint256 lp0TransferAmount = lp0BalAfter - lp0BalBefore;
        uint256 lp1TransferAmount = lp1BalAfter - lp1BalBefore;
        return (lp0TransferAmount, lp1TransferAmount, wantBal);
    }


    // withdraws funds and sends them back to the vault
    function withdraw(uint256 wantAmount) external onlyVault {
        (uint256 lp0TransferAmount, uint256 lp1TransferAmount, uint256 wantBal) = startWithdraw(wantAmount);
        uint256 inputBalBefore = IERC20(inputToken).balanceOf(address(this));
        swapLpTokens(lp0TransferAmount, lp1TransferAmount, lp0ToInputTokenRoute, lp1ToInputTokenRoute);
        uint256 inputBalAfter = IERC20(inputToken).balanceOf(address(this));
        uint256 inputBal = inputBalAfter - inputBalBefore;
        IERC20(inputToken).safeTransfer(vault, inputBal);
        emit Withdraw(wantBal);
    }

    function withdrawAsLpTokens(uint256 wantAmount) external onlyVault {
        (uint256 lp0TransferAmount, uint256 lp1TransferAmount, uint256 wantBal) = startWithdraw(wantAmount);
        IERC20(lp0Token).safeTransfer(vault, lp0TransferAmount);
        IERC20(lp1Token).safeTransfer(vault, lp1TransferAmount);
        emit Withdraw(wantBal);
    }

    function beforeDeposit() external virtual {
        if (harvestOnDeposit) {
            require(msg.sender == vault, "!vault");
            _harvest();
        }
    }

    function harvest() external gasThrottle virtual {
        _harvest();
    }

    // compounds earnings and charges performance fee
    function _harvest() internal whenNotPaused {
        IGauge(gauge).getReward(address(this), rewards);
        uint256 outputBal = IERC20(rewardToken).balanceOf(address(this));
        if (outputBal > 0) {
            chargeFees();
            addLiquidityFromSingleToken(rewardToken, rewardTokenToLp0TokenRoute, rewardTokenToLp1TokenRoute);
            uint256 wantHarvested = balanceOfWant();
            depositWant();
            lastHarvest = block.timestamp;
            emit StratHarvest(msg.sender, wantHarvested, balanceOf());
        }
    }

    // performance fees
    function chargeFees() internal {
        uint256 rewardTokenBalance = IERC20(rewardToken).balanceOf(address(this));
        uint256 totalFeeAmount = rewardTokenBalance * (DEV_FEE + STAKING_FEE) / DIVISOR;

        if (totalFeeAmount > 0) {
            uint totalFee = DEV_FEE + STAKING_FEE;
            swapToken(totalFeeAmount, rewardTokenToFeeTokenRoute);
            uint256 feeTokenBalance = IERC20(feeToken).balanceOf(address(this));
            uint devFee = DEV_FEE * feeTokenBalance / totalFee;
            IERC20(feeToken).safeTransfer(devFeeAddress, devFee);

            if (STAKING_FEE > 0) {
                uint256 stakingFee = feeTokenBalance - devFee;
                IERC20(feeToken).safeTransfer(stakingAddress, stakingFee);
            }

            emit ChargedFees(DEV_FEE + STAKING_FEE, totalFeeAmount);
        }
        emit CollectRewards(rewardTokenBalance);
    }

    // Adds liquidity to AMM and gets more LP tokens.
    function addLiquidityFromSingleToken(address tokenToDeposit, ISolidlyRouter.Routes[] memory tokenToLp0Route, ISolidlyRouter.Routes[] memory tokenToLp1Route) internal {
        uint256 outputBal = IERC20(tokenToDeposit).balanceOf(address(this));
        uint256 lp0Amt = outputBal / 2;
        uint256 lp1Amt = outputBal - lp0Amt;

        // NB stable pools use a different model for LP compared to volatile
        if (isStable) {
            uint256 lp0Decimals = 10 ** ERC20(lp0Token).decimals();
            uint256 lp1Decimals = 10 ** ERC20(lp1Token).decimals();
            uint256 out0 = ISolidlyRouter(router).getAmountsOut(lp0Amt, tokenToLp0Route)[tokenToLp0Route.length] * 1e18 / lp0Decimals;
            uint256 out1 = ISolidlyRouter(router).getAmountsOut(lp1Amt, tokenToLp1Route)[tokenToLp1Route.length] * 1e18 / lp1Decimals;
            (uint256 amountA, uint256 amountB,) = ISolidlyRouter(router).quoteAddLiquidity(lp0Token, lp1Token, isStable, out0, out1);
            amountA = amountA * 1e18 / lp0Decimals;
            amountB = amountB * 1e18 / lp1Decimals;
            uint256 ratio = out0 * 1e18 / out1 * amountB / amountA;
            lp0Amt = outputBal * 1e18 / (ratio + 1e18);
            lp1Amt = outputBal - lp0Amt;
        }

        // Swap reward token for lp0 token
        if (lp0Token != rewardToken) {
            swapToken(lp0Amt, tokenToLp0Route);
        }

        // Swap reward token for lp1 token
        if (lp1Token != rewardToken) {
            swapToken(lp1Amt, tokenToLp1Route);
        }

        uint256 lp0Bal = IERC20(lp0Token).balanceOf(address(this));
        uint256 lp1Bal = IERC20(lp1Token).balanceOf(address(this));
        // Add liquidity for lp tokens
        addLiquidity(lp0Token, lp1Token, isStable, lp0Bal, lp1Bal, 1, 1, block.timestamp);
    }

    // calculate the total underlying 'want' held by the strat.
    function balanceOf() public view returns (uint256) {
        return balanceOfWant() + balanceOfPool();
    }

    // calculates how much 'want' this contract holds. NB the want is the LP token
    function balanceOfWant() public view returns (uint256) {
        return IERC20(wantToken).balanceOf(address(this));
    }

    // it calculates how much 'want' the strategy has working in the farm.
    function balanceOfPool() public view returns (uint256) {
        uint256 _amount = IGauge(gauge).balanceOf(address(this));
        return _amount;
    }

    function lpTokenBalances() public view returns (uint256, uint256) {
        return (IERC20(lp0Token).balanceOf(address(this)), IERC20(lp1Token).balanceOf(address(this)));
    }

    // returns rewards unharvested
    function rewardsAvailable() public view returns (uint256) {
        return IGauge(gauge).earned(rewardToken, address(this));
    }

    function setHarvestOnDeposit(bool _harvestOnDeposit) external onlyManagerAndOwner {
        harvestOnDeposit = _harvestOnDeposit;
    }

    function setShouldGasThrottle(bool _shouldGasThrottle) external onlyManagerAndOwner {
        shouldGasThrottle = _shouldGasThrottle;
    }
    // called as part of strat migration. Sends all the available funds back to the vault.
    function retireStrat() external {
        require(msg.sender == vault, "!vault");

        IGauge(gauge).withdraw(balanceOfPool());

        uint256 wantBal = IERC20(wantToken).balanceOf(address(this));
        IERC20(wantToken).transfer(vault, wantBal);
    }

    // pauses deposits and withdraws all funds from third party systems.
    function panic() public onlyManagerAndOwner {
        pause();
        IGauge(gauge).withdraw(balanceOfPool());
    }

    function pause() public onlyManagerAndOwner {
        _pause();

        _removeAllowances();
    }

    function unpause() public onlyManagerAndOwner {
        _unpause();

        _giveAllowances();

        deposit();
    }

    function _giveAllowances() internal {
        IERC20(wantToken).safeApprove(gauge, type(uint).max);
        IERC20(rewardToken).safeApprove(router, type(uint).max);
        IERC20(inputToken).safeApprove(router, type(uint).max);
        IERC20(wantToken).safeApprove(router, type(uint).max);
        IERC20(feeToken).safeApprove(router, 0);
        IERC20(feeToken).safeApprove(router, type(uint).max);
        IERC20(lp0Token).safeApprove(router, 0);
        IERC20(lp0Token).safeApprove(router, type(uint).max);
        IERC20(lp1Token).safeApprove(router, 0);
        IERC20(lp1Token).safeApprove(router, type(uint).max);
    }

    function _removeAllowances() internal {
        IERC20(rewardToken).safeApprove(router, 0);
        IERC20(lp0Token).safeApprove(router, 0);
        IERC20(lp1Token).safeApprove(router, 0);
        IERC20(inputToken).safeApprove(router, 0);
        IERC20(feeToken).safeApprove(router, 0);
        IERC20(wantToken).safeApprove(gauge, 0);
        IERC20(wantToken).safeApprove(router, 0);
    }

    function getRewardTokenToFeeTokenRoute() external view returns (address[] memory) {
        ISolidlyRouter.Routes[] memory _route = rewardTokenToFeeTokenRoute;
        return solidlyToUniRoute(_route);
    }

    function getRewardTokenToLp0TokenRoute() external view returns (address[] memory) {
        ISolidlyRouter.Routes[] memory _route = rewardTokenToLp0TokenRoute;
        return solidlyToUniRoute(_route);
    }

    function getRewardTokenToLp1TokenRoute() external view returns (address[] memory) {
        ISolidlyRouter.Routes[] memory _route = rewardTokenToLp1TokenRoute;
        return solidlyToUniRoute(_route);
    }

    function setTokenId(uint256 _tokenId) external onlyOwner {
        tokenId = _tokenId;
    }

    function want() external view returns (address) {
        return wantToken;
    }

    function reward() external view returns (address) {
        return rewardToken;
    }

    function lp0() external view returns (address) {
        return lp0Token;
    }

    function lp1() external view returns (address) {
        return lp1Token;
    }

    function input() external view returns (address) {
        return inputToken;
    }
    
    function fee() external view returns (address) {
        return feeToken;
    }

    function stop() public onlyOwner {
        _harvest();
        _stop();
        _removeAllowances();
    }

    function resume() public onlyOwner {
        _resume();
        _giveAllowances();
        deposit();
    }
}

