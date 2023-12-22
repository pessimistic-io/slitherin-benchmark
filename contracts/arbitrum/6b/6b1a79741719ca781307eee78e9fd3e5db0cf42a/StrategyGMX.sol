// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./ERC20.sol";
import "./SafeERC20.sol";
import "./IGMXRouter.sol";
import "./IGMXTracker.sol";
import "./IGMXStrategy.sol";
import "./StratFeeManager.sol";
import "./GasFeeThrottler.sol";
import "./IUniswapRouterV3.sol";

contract StrategyGMX is StrategyManager, GasFeeThrottler {
    using SafeERC20 for IERC20;

    address public native;
    address public wantToken;

    address public chef;
    address public rewardStorage;
    address public balanceTracker;

    bool public harvestOnDeposit;
    uint256 public lastHarvest;
    uint256 public lastDepositTime;

    address public stakingAddress;
    address public devFeeAddress;
    uint256 STAKING_FEE = 0;
    uint DEV_FEE = 5 * 10 ** 16;
    uint DIVISOR = 10 ** 18;
    uint MAX_FEE = 5 * 10 ** 17;

    event StratHarvest(address indexed harvester, uint256 wantTokenHarvested, uint256 tvl);
    event Deposit(uint256 tvl);
    event Withdraw(uint256 tvl);
    event ChargedFees(uint256 fees, uint256 amount);

    constructor(
        address _chef,
        CommonAddresses memory _commonAddresses
    ) StrategyManager(_commonAddresses) {
        chef = _chef;
        rewardStorage = IGMXRouter(chef).feeGmxTracker();
        balanceTracker = IGMXRouter(chef).stakedGmxTracker();
        devFeeAddress = _msgSender();
    }

    function want() external view returns (address) {
        return wantToken;
    }

    // puts the funds to work
    function deposit() public whenNotStopped {
        uint256 wantTokenBal = IERC20(wantToken).balanceOf(address(this));

        if (wantTokenBal > 0) {
            IGMXRouter(chef).stakeGmx(wantTokenBal);
            lastDepositTime = block.timestamp;
            emit Deposit(wantTokenBal);
        }
    }

    function withdraw(uint256 _amount) external {
        require(msg.sender == vault, "!vault");
        uint256 wantTokenBal = IERC20(wantToken).balanceOf(address(this));
        if (wantTokenBal < _amount) {
            IGMXRouter(chef).unstakeGmx(_amount - wantTokenBal);
            wantTokenBal = IERC20(wantToken).balanceOf(address(this));
        }

        if (wantTokenBal > _amount) {
            wantTokenBal = _amount;
        }

        IERC20(wantToken).safeTransfer(vault, wantTokenBal);
        emit Withdraw(wantTokenBal);
    }

    function beforeDeposit() external virtual override {
        if (harvestOnDeposit) {
            require(msg.sender == vault, "!vault");
            _harvest();
        }
    }

    function harvest() external gasThrottle virtual {
        _harvest();
    }

    // compounds earnings and charges performance fee
    function _harvest() internal whenNotStopped {
        IGMXRouter(chef).compound();
        // Claim and re-stake esGMX and multiplier points
        IGMXTracker(rewardStorage).claim(address(this));
        uint256 nativeBal = IERC20(native).balanceOf(address(this));
        if (nativeBal > 0) {
            chargeFees();
            swapRewards();
            uint256 wantTokenHarvested = balanceOfWant();
            deposit();
            lastHarvest = block.timestamp;
            emit StratHarvest(msg.sender, wantTokenHarvested, balanceOf());
        }
    }

    // performance fees
    function chargeFees() internal {
        uint256 devFeeAmount = IERC20(native).balanceOf(address(this)) * DEV_FEE / DIVISOR;
        uint256 stakingFeeAmount = IERC20(native).balanceOf(address(this)) * STAKING_FEE / DIVISOR;
        IERC20(native).safeTransfer(devFeeAddress, devFeeAmount);

        if (stakingFeeAmount > 0) {
            IERC20(native).safeTransfer(stakingAddress, stakingFeeAmount);
        }

        emit ChargedFees(DEV_FEE, devFeeAmount + stakingFeeAmount);
    }

    // Adds liquidity to AMM and gets more LP tokens.
    function swapRewards() internal virtual {
        uint256 nativeBal = IERC20(native).balanceOf(address(this));
        if (nativeBal > 0) {
            IUniswapRouterV3.ExactInputSingleParams memory params = IUniswapRouterV3.ExactInputSingleParams({
                tokenIn: native,
                tokenOut: wantToken,
                fee: 3000,
                recipient: address(this),
                amountIn: nativeBal,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });
            IUniswapRouterV3(unirouter).exactInputSingle(params);
        }
    }

    // calculate the total underlaying 'wantToken' held by the strat.
    function balanceOf() public view returns (uint256) {
        return balanceOfWant() + balanceOfPool();
    }

    // it calculates how much 'wantToken' this contract holds.
    function balanceOfWant() public view returns (uint256) {
        return IERC20(wantToken).balanceOf(address(this));
    }

    // it calculates how much 'wantToken' the strategy has working in the farm.
    function balanceOfPool() public view returns (uint256) {
        return IGMXTracker(balanceTracker).depositBalances(address(this), wantToken);
    }

    // returns rewards unharvested
    function rewardsAvailable() public view returns (uint256) {
        return IGMXTracker(rewardStorage).claimable(address(this));
    }

    // native reward amount for calling harvest
    function callReward() public view returns (uint256) {}

    function setHarvestOnDeposit(bool _harvestOnDeposit) external onlyOwner {
        harvestOnDeposit = _harvestOnDeposit;
    }

    function setDevFee(uint fee) external onlyOwner {
        require(fee + STAKING_FEE <= MAX_FEE, "fee too high");
        DEV_FEE = fee;
    }

    function setStakingFee(uint fee) external onlyOwner {
        require(fee + DEV_FEE <= MAX_FEE, "fee too high");
        STAKING_FEE = fee;
    }

    function getDevFee() external view returns (uint256) {
        return DEV_FEE;
    }

    function getStakingFee() external view returns (uint256) {
        return STAKING_FEE;
    }

    function setStakingAddress(address _stakingAddress) external onlyOwner {
        stakingAddress = _stakingAddress;
    }

    function setDevFeeAddress(address _devFeeAddress) external onlyOwner {
        devFeeAddress = _devFeeAddress;
    }

    function setShouldGasThrottle(bool _shouldGasThrottle) external onlyOwner {
        shouldGasThrottle = _shouldGasThrottle;
    }

    // stops deposits and withdraws all funds from third party systems.
    function panic() public onlyOwner {
        stop();
        IGMXRouter(chef).unstakeGmx(balanceOfPool());
    }

    function stop() public onlyOwner {
        _harvest();
        _stop();
        _removeAllowances();
    }

    function resume() external onlyOwner {
        _resume();
        _giveAllowances();
        deposit();
    }

    function _giveAllowances() internal {
        IERC20(wantToken).safeApprove(balanceTracker, type(uint).max);
        IERC20(native).safeApprove(unirouter, type(uint).max);
    }

    function _removeAllowances() internal {
        IERC20(wantToken).safeApprove(balanceTracker, 0);
        IERC20(native).safeApprove(unirouter, 0);
    }

    function nativeToWant() external view virtual returns (address[] memory) {}

}

