// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

import "./ERC20.sol";
import "./SafeERC20.sol";
import "./SafeMath.sol";
import "./Ownable.sol";
import "./Pausable.sol";

import "./IUniswapRouterETH.sol";
import "./IMasterChef.sol";
import "./IStargateRouter.sol";
import "./StringUtils.sol";
import "./GasThrottler.sol";

import "./IFeeTierStrate.sol";

contract StrategyStargateStaking is Ownable, Pausable, GasThrottler {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    // Tokens used
    address public native;
    address public output;
    address public want;
    address public lpToken0;

    // Third party contracts
    address public chef;
    uint256 public poolId;
    address public stargateRouter;
    uint256 public routerPoolId;

    address public unirouter;
    address public vault;
    address public feeStrate;

    bool public harvestOnDeposit;
    uint256 public lastHarvest;
    string public pendingRewardsFunctionName;

    // Routes
    address[] public outputToNativeRoute;
    address[] public outputToLp0Route;
    address[] public outputToLp1Route;

    event StratHarvest(address indexed harvester, uint256 wantHarvested, uint256 tvl);
    event Deposit(uint256 tvl);
    event Withdraw(uint256 tvl);
    event ChargedFees(uint256 callFees, uint256 beefyFees, uint256 strategistFees);

    constructor(
        address _want,
        uint256 _poolId,
        uint256 _routerPoolId,
        address _chef,
        address _vault,
        address _unirouter,
        address _stargateRouter,
        address _feeStrate,
        address[] memory _outputToNativeRoute,
        address[] memory _outputToLp0Route
    ) public {
        want = _want;
        poolId = _poolId;
        routerPoolId = _routerPoolId;
        chef = _chef;
        stargateRouter = _stargateRouter;

        unirouter = _unirouter;
        vault = _vault;
        feeStrate = _feeStrate;

        output = _outputToNativeRoute[0];
        native = _outputToNativeRoute[_outputToNativeRoute.length - 1];
        outputToNativeRoute = _outputToNativeRoute;

        // setup lp routing
        outputToLp0Route = _outputToLp0Route;
        lpToken0 = _outputToLp0Route[_outputToLp0Route.length - 1];

        _giveAllowances();
    }

    /**
     * @dev Updates router that will be used for swaps.
     * @param _unirouter new unirouter address.
     */
    function setUnirouter(address _unirouter) external onlyOwner {
        unirouter = _unirouter;
    }

    /**
     * @dev Updates parent vault.
     * @param _vault new vault address.
     */
    function setVault(address _vault) external onlyOwner {
        vault = _vault;
    }

    /**
     * @dev Updates parent fee strate.
     * @param _feeStrate new fee strate address.
     */
    function setFeeStrate(address _feeStrate) external onlyOwner {
        feeStrate = _feeStrate;
    }

    // puts the funds to work
    function deposit() public whenNotPaused {
        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal > 0) {
            IMasterChef(chef).deposit(poolId, wantBal);
            emit Deposit(balanceOf());
        }
    }

    function afterDepositFee(uint256 shares) public view returns(uint256) {
        if (tx.origin != owner() && !paused()) {
            (uint256 depositFee, uint256 baseFee) = IFeeTierStrate(feeStrate).getDepositFee();
            uint256 depositFeeAmount = shares.mul(depositFee).div(baseFee);
            shares = shares.sub(depositFeeAmount);
        }
        return shares;
    }

    function withdraw(uint256 _amount) external returns(uint256) {
        require(msg.sender == vault, "!vault");

        uint256 withAmount = _amount;
        uint256 feeAmount = 0;
        if (tx.origin != owner() && !paused()) {
            (uint256 withdrawlFee, uint256 baseFee) = IFeeTierStrate(feeStrate).getWithdrawFee();
            feeAmount = withAmount.mul(withdrawlFee).div(baseFee);
            withAmount = withAmount.sub(feeAmount);
        }

        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal < withAmount) {
            IMasterChef(chef).withdraw(poolId, withAmount.sub(wantBal));
            wantBal = IERC20(want).balanceOf(address(this));
        }

        if (wantBal > withAmount) {
            wantBal = withAmount;
        }

        IERC20(want).safeTransfer(vault, wantBal);

        emit Withdraw(balanceOf());

        return feeAmount;
    }

    function withdrawFee(uint256 _amount) external {
        require(msg.sender == vault, "!vault");

        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal < _amount) {
            IMasterChef(chef).withdraw(poolId, _amount.sub(wantBal));
            wantBal = IERC20(want).balanceOf(address(this));
        }

        if (wantBal > _amount) {
            wantBal = _amount;
        }

        uint256[] memory feeIndexs = IFeeTierStrate(feeStrate).getAllTier();
        uint256 len = feeIndexs.length;
        uint256 maxFee = IFeeTierStrate(feeStrate).getMaxFee();
        for (uint256 i=0; i<len; i++) {
            (address feeAccount, ,uint256 fee) = IFeeTierStrate(feeStrate).getTier(feeIndexs[i]);
            uint256 feeAmount = wantBal.mul(fee).div(maxFee);
            if (feeAmount > 0) {
                IERC20(want).safeTransfer(feeAccount, feeAmount);
            }
        }
    }

    function beforeDeposit() external {
        if (harvestOnDeposit) {
            require(msg.sender == vault, "!vault");
            _harvest();
        }
    }

    function harvest() external gasThrottle virtual {
        _harvest();
    }

    function managerHarvest() external onlyOwner {
        _harvest();
    }

    // compounds earnings and charges performance fee
    function _harvest() internal whenNotPaused {
        IMasterChef(chef).deposit(poolId, 0);
        uint256 outputBal = IERC20(output).balanceOf(address(this));
        if (outputBal > 0) {
            chargeFees();
            addLiquidity();
            uint256 wantHarvested = balanceOfWant();
            deposit();

            lastHarvest = block.timestamp;
            emit StratHarvest(msg.sender, wantHarvested, balanceOf());
        }
    }

    // performance fees
    function chargeFees() internal {
        (uint256 totalFee, uint256 baseFee) = IFeeTierStrate(feeStrate).getTotalFee();

        uint256 toNative = IERC20(output).balanceOf(address(this)).mul(totalFee).div(baseFee);
        IUniswapRouterETH(unirouter).swapExactTokensForTokens(toNative, 0, outputToNativeRoute, address(this), block.timestamp);

        uint256 nativeBal = IERC20(native).balanceOf(address(this));

        uint256[] memory feeIndexs = IFeeTierStrate(feeStrate).getAllTier();
        uint256 len = feeIndexs.length;
        uint256 maxFee = IFeeTierStrate(feeStrate).getMaxFee();
        for (uint256 i=0; i<len; i++) {
            (address feeAccount, ,uint256 fee) = IFeeTierStrate(feeStrate).getTier(feeIndexs[i]);
            uint256 feeAmount = nativeBal.mul(fee).div(maxFee);
            if (feeAmount > 0) {
                IERC20(native).safeTransfer(feeAccount, feeAmount);
            }
        }
    }

    // Adds liquidity to AMM and gets more LP tokens.
    function addLiquidity() internal {
        uint256 outputBal = IERC20(output).balanceOf(address(this));

        if (lpToken0 != output) {
            IUniswapRouterETH(unirouter).swapExactTokensForTokens(outputBal, 0, outputToLp0Route, address(this), block.timestamp);
        }

        uint256 lp0Bal = IERC20(lpToken0).balanceOf(address(this));
        IStargateRouter(stargateRouter).addLiquidity(routerPoolId, lp0Bal, address(this));
    }

    // calculate the total underlaying 'want' held by the strat.
    function balanceOf() public view returns (uint256) {
        return balanceOfWant().add(balanceOfPool());
    }

    // it calculates how much 'want' this contract holds.
    function balanceOfWant() public view returns (uint256) {
        return IERC20(want).balanceOf(address(this));
    }

    // it calculates how much 'want' the strategy has working in the farm.
    function balanceOfPool() public view returns (uint256) {
        (uint256 _amount,) = IMasterChef(chef).userInfo(poolId, address(this));
        return _amount;
    }

    function setPendingRewardsFunctionName(string calldata _pendingRewardsFunctionName) external onlyOwner {
        pendingRewardsFunctionName = _pendingRewardsFunctionName;
    }

    // returns rewards unharvested
    function rewardsAvailable() public view returns (uint256) {
        string memory signature = StringUtils.concat(pendingRewardsFunctionName, "(uint256,address)");
        bytes memory result = Address.functionStaticCall(
            chef, 
            abi.encodeWithSignature(
                signature,
                poolId,
                address(this)
            )
        );  
        return abi.decode(result, (uint256));
    }

    // native reward amount for calling harvest
    function callReward() public view returns (uint256) {
        uint256 outputBal = rewardsAvailable();
        uint256 nativeOut;
        if (outputBal > 0) {
            uint256[] memory amountOut = IUniswapRouterETH(unirouter).getAmountsOut(outputBal, outputToNativeRoute);
            nativeOut = amountOut[amountOut.length -1];
        }

        (uint256 totalFee, uint256 baseFee) = IFeeTierStrate(feeStrate).getTotalFee();
        return nativeOut.mul(totalFee).div(baseFee);
    }

    function setHarvestOnDeposit(bool _harvestOnDeposit) external onlyOwner {
        harvestOnDeposit = _harvestOnDeposit;
    }

    function setShouldGasThrottle(bool _shouldGasThrottle) external onlyOwner {
        shouldGasThrottle = _shouldGasThrottle;
    }

    // called as part of strat migration. Sends all the available funds back to the vault.
    function retireStrat() external {
        require(msg.sender == vault, "!vault");

        IMasterChef(chef).emergencyWithdraw(poolId);

        uint256 wantBal = IERC20(want).balanceOf(address(this));
        IERC20(want).transfer(vault, wantBal);
    }

    // pauses deposits and withdraws all funds from third party systems.
    function panic() public onlyOwner {
        pause();
        IMasterChef(chef).emergencyWithdraw(poolId);
    }

    function pause() public onlyOwner {
        _pause();

        _removeAllowances();
    }

    function unpause() external onlyOwner {
        _unpause();

        _giveAllowances();

        deposit();
    }

    function _giveAllowances() internal {
        IERC20(want).safeApprove(chef, uint256(-1));
        IERC20(output).safeApprove(unirouter, uint256(-1));

        IERC20(lpToken0).safeApprove(stargateRouter, 0);
        IERC20(lpToken0).safeApprove(stargateRouter, uint256(-1));
    }

    function _removeAllowances() internal {
        IERC20(want).safeApprove(chef, 0);
        IERC20(output).safeApprove(unirouter, 0);
        IERC20(lpToken0).safeApprove(stargateRouter, 0);
    }

    function outputToNative() external view returns (address[] memory) {
        return outputToNativeRoute;
    }

    function outputToLp0() external view returns (address[] memory) {
        return outputToLp0Route;
    }
}

