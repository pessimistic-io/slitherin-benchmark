// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./SafeERC20.sol";

import "./IAutoPool.sol";
import "./IAutoPoolFarm.sol";
import "./ILBRouter.sol";
import "./StratFeeManagerInitializable.sol";
import "./GasFeeThrottler.sol";

contract StrategyAutoPool is StratFeeManagerInitializable, GasFeeThrottler {
    using SafeERC20 for IERC20;

    // Tokens used
    address public native;
    address public output;
    address public reward;
    address public want;
    address public depositToken;
    address public outputPair;

    // Third party contracts
    address public chef;
    uint256 public poolId;

    bool public harvestOnDeposit;
    uint256 public lastHarvest;
    uint256 public depositIndex;
    bool public swapForY;

    // Routes
    ILBRouter.Path outputToNativePath;
    ILBRouter.Path nativeToDepositPath;
    ILBRouter.Path rewardToNativePath;

    event StratHarvest(address indexed harvester, uint256 wantHarvested, uint256 tvl);
    event Deposit(uint256 tvl);
    event Withdraw(uint256 tvl);
    event ChargedFees(uint256 callFees, uint256 beefyFees, uint256 strategistFees);

    function initialize(
        address _want,
        uint256 _poolId,
        address _chef,
        ILBRouter.Path calldata _outputToNativePath,
        ILBRouter.Path calldata _nativeToDepositPath,
        ILBRouter.Path calldata _rewardToNativePath,
        address _outputPair,
        bool _swapForY,
        CommonAddresses calldata _commonAddresses
    ) public initializer {
        __StratFeeManager_init(_commonAddresses);
        want = _want;
        poolId = _poolId;
        chef = _chef;

        output = _outputToNativePath.tokenPath[0];
        reward = _rewardToNativePath.tokenPath[0];
        native = _outputToNativePath.tokenPath[_outputToNativePath.tokenPath.length - 1];

        require(_nativeToDepositPath.tokenPath[0] == native, "nativeToDepositRoute[0] != native");
        depositToken = _nativeToDepositPath.tokenPath[_nativeToDepositPath.tokenPath.length - 1];

        depositIndex = depositToken == IAutoPool(want).getTokenX() ? 0 : 1;
        outputPair = _outputPair;
        swapForY = _swapForY;

        outputToNativePath.pairBinSteps = _outputToNativePath.pairBinSteps;
        outputToNativePath.versions = _outputToNativePath.versions;
        outputToNativePath.tokenPath = _outputToNativePath.tokenPath;

        nativeToDepositPath.pairBinSteps = _nativeToDepositPath.pairBinSteps;
        nativeToDepositPath.versions = _nativeToDepositPath.versions;
        nativeToDepositPath.tokenPath = _nativeToDepositPath.tokenPath;

        rewardToNativePath.pairBinSteps = _rewardToNativePath.pairBinSteps;
        rewardToNativePath.versions = _rewardToNativePath.versions;
        rewardToNativePath.tokenPath = _rewardToNativePath.tokenPath;

        _giveAllowances();
    }

    // puts the funds to work
    function deposit() public whenNotPaused {
        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal > 0) {
            IAutoPoolFarm(chef).deposit(poolId, wantBal);
            emit Deposit(balanceOf());
        }
    }

    function withdraw(uint256 _amount) external {
        require(msg.sender == vault, "!vault");

        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal < _amount) {
            IAutoPoolFarm(chef).withdraw(poolId, _amount - wantBal);
            wantBal = IERC20(want).balanceOf(address(this));
        }

        if (wantBal > _amount) {
            wantBal = _amount;
        }

        if (tx.origin != owner() && !paused()) {
            uint256 withdrawalFeeAmount = wantBal * withdrawalFee / WITHDRAWAL_MAX;
            wantBal = wantBal - withdrawalFeeAmount;
        }

        IERC20(want).safeTransfer(vault, wantBal);

        emit Withdraw(balanceOf());
    }

    function beforeDeposit() external virtual override {
        if (harvestOnDeposit) {
            require(msg.sender == vault, "!vault");
            _harvest(tx.origin);
        }
    }

    function harvest() external gasThrottle virtual {
        _harvest(tx.origin);
    }

    function harvest(address callFeeRecipient) external gasThrottle virtual {
        _harvest(callFeeRecipient);
    }

    function managerHarvest() external onlyManager {
        _harvest(tx.origin);
    }

    // compounds earnings and charges performance fee
    function _harvest(address callFeeRecipient) internal whenNotPaused {
        uint256[] memory poolIds = new uint256[](1);
        poolIds[0] = poolId;
        IAutoPoolFarm(chef).harvestRewards(poolIds);
        uint256 outputBal = IERC20(output).balanceOf(address(this));
        if (outputBal > 0) {
            swapRewards();
            chargeFees(callFeeRecipient);
            addLiquidity();
            uint256 wantHarvested = balanceOfWant();
            deposit();

            lastHarvest = block.timestamp;
            emit StratHarvest(msg.sender, wantHarvested, balanceOf());
        }
    }

    // performance fees
    function chargeFees(address callFeeRecipient) internal {
        IFeeConfig.FeeCategory memory fees = getFees();
        uint256 nativeBal = IERC20(native).balanceOf(address(this)) * fees.total / DIVISOR;

        uint256 callFeeAmount = nativeBal * fees.call / DIVISOR;
        IERC20(native).safeTransfer(callFeeRecipient, callFeeAmount);

        uint256 beefyFeeAmount = nativeBal * fees.beefy / DIVISOR;
        IERC20(native).safeTransfer(beefyFeeRecipient, beefyFeeAmount);

        uint256 strategistFeeAmount = nativeBal * fees.strategist / DIVISOR;
        IERC20(native).safeTransfer(strategist, strategistFeeAmount);

        emit ChargedFees(callFeeAmount, beefyFeeAmount, strategistFeeAmount);
    }

    function swapRewards() internal {
        uint256 outputBal = IERC20(output).balanceOf(address(this));
        uint256 rewardBal = IERC20(reward).balanceOf(address(this));

        if (outputBal > 0) ILBRouter(unirouter).swapExactTokensForTokens(outputBal, 0, outputToNativePath, address(this), block.timestamp);
        if (rewardBal > 0) ILBRouter(unirouter).swapExactTokensForTokens(rewardBal, 0, rewardToNativePath, address(this), block.timestamp);
    }

    // Adds liquidity to AMM and gets more LP tokens.
    function addLiquidity() internal {
        uint256 nativeBal = IERC20(native).balanceOf(address(this));
        if (depositToken != output) {
            ILBRouter(unirouter).swapExactTokensForTokens(
                nativeBal, 0, nativeToDepositPath, address(this), block.timestamp
            );
        }

        uint256 depositBal = IERC20(depositToken).balanceOf(address(this));
        uint256 token0Bal;
        uint256 token1Bal;
        if (depositIndex == 0) {
            token0Bal = depositBal;
        } else {
            token1Bal = depositBal;
        }

        IAutoPool(want).deposit(token0Bal, token1Bal);
    }

    // calculate the total underlaying 'want' held by the strat.
    function balanceOf() public view returns (uint256) {
        return balanceOfWant() + balanceOfPool();
    }

    // it calculates how much 'want' this contract holds.
    function balanceOfWant() public view returns (uint256) {
        return IERC20(want).balanceOf(address(this));
    }

    // it calculates how much 'want' the strategy has working in the farm.
    function balanceOfPool() public view returns (uint256) {
        (uint256 _amount,,) = IAutoPoolFarm(chef).userInfo(poolId, address(this));
        return _amount;
    }

    // returns rewards unharvested
    function rewardsAvailable() public view returns (uint256 amount) {
        (amount,,,) = IAutoPoolFarm(chef).pendingTokens(poolId, address(this));
    }

    // native reward amount for calling harvest
    function callReward() public view returns (uint256) {
        IFeeConfig.FeeCategory memory fees = getFees();
        uint256 outputBal = rewardsAvailable();
        uint256 nativeOut;
        if (outputBal > 0) {
            (,nativeOut,) = ILBRouter(unirouter).getSwapOut(outputPair, uint128(outputBal), swapForY);
        }

        return nativeOut * fees.total / DIVISOR * fees.call / DIVISOR;
    }

    function setHarvestOnDeposit(bool _harvestOnDeposit) external onlyManager {
        harvestOnDeposit = _harvestOnDeposit;

        if (harvestOnDeposit) {
            setWithdrawalFee(0);
        } else {
            setWithdrawalFee(10);
        }
    }

    function setShouldGasThrottle(bool _shouldGasThrottle) external onlyManager {
        shouldGasThrottle = _shouldGasThrottle;
    }

    // called as part of strat migration. Sends all the available funds back to the vault.
    function retireStrat() external {
        require(msg.sender == vault, "!vault");

        IAutoPoolFarm(chef).emergencyWithdraw(poolId);

        uint256 wantBal = IERC20(want).balanceOf(address(this));
        IERC20(want).transfer(vault, wantBal);
    }

    // pauses deposits and withdraws all funds from third party systems.
    function panic() public onlyManager {
        pause();
        IAutoPoolFarm(chef).emergencyWithdraw(poolId);
    }

    function pause() public onlyManager {
        _pause();

        _removeAllowances();
    }

    function unpause() external onlyManager {
        _unpause();

        _giveAllowances();

        deposit();
    }

    function _giveAllowances() internal {
        IERC20(want).safeApprove(chef, type(uint).max);
        IERC20(output).safeApprove(unirouter, type(uint).max);
        IERC20(native).safeApprove(unirouter, type(uint).max);
        IERC20(reward).safeApprove(unirouter, type(uint).max);

        IERC20(depositToken).safeApprove(want, 0);
        IERC20(depositToken).safeApprove(want, type(uint).max);
    }

    function _removeAllowances() internal {
        IERC20(want).safeApprove(chef, 0);
        IERC20(output).safeApprove(unirouter, 0);
        IERC20(depositToken).safeApprove(want, 0);
        IERC20(native).safeApprove(unirouter, 0);
        IERC20(reward).safeApprove(unirouter, 0);
    }

    function outputToNative() external view returns (address[] memory) {
        return outputToNativePath.tokenPath;
    }

    function nativeToDeposit() external view returns (address[] memory) {
        return nativeToDepositPath.tokenPath;
    }

    function rewardToNative() external view returns (address[] memory) {
        return rewardToNativePath.tokenPath;
    }
}
