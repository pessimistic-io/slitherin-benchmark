// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./ERC20.sol";
import "./SafeERC20.sol";
import "./IBFRRouter.sol";
import "./IBFRTracker.sol";
import "./StratFeeManager.sol";
import "./GasFeeThrottler.sol";
import "./IUniswapRouterV3.sol";
import "./UniSwapRoutes.sol";

contract StrategyBFR is Manager, GasFeeThrottler, UniSwapRoutes, Stoppable {
    using SafeERC20 for IERC20;

    address public rewardToken;
    address public wantToken;
    address public vault;
    address public arbToken; //= 0x912CE59144191C1204E64559FE8253a0e49E6548;
    address public wethToken; //= 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;

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
        address _vault,
        address _uniRouter,
        address _wantToken,
        address _arbToken,
        address _rewardToken,
        address _wethToken
    ) {
        chef = _chef;
        rewardStorage = IBFRRouter(chef).feeBfrTracker();
        balanceTracker = IBFRRouter(chef).stakedBfrTracker();
        devFeeAddress = _msgSender();
        wantToken = _wantToken;
        vault = _vault;
        rewardToken = _rewardToken;
        arbToken = _arbToken;
        wethToken = _wethToken;
        setRewardRouteParams(_uniRouter);
        IERC20(wantToken).safeApprove(balanceTracker, type(uint).max);
    }

    function setRewardRouteParams(address unirouter) internal {
        setUniRouter(unirouter);
        address[] memory path1 = new address[](3);
        path1[0] = rewardToken;
        path1[1] = wethToken;
        path1[2] = wantToken;
        uint24[] memory fees = new uint24[](2);
        fees[0] = 500;
        fees[1] = 10000;
        registerRoute(path1, fees);

        address[] memory path2 = new address[](3);
        path2[0] = arbToken;
        path2[1] = wethToken;
        path2[2] = wantToken;
        uint24[] memory fees2 = new uint24[](2);
        fees2[0] = 500;
        fees2[1] = 3000;
        registerRoute(path2, fees2);
        address[] memory tokens = new address[](2);
        tokens[0] = rewardToken;
        tokens[1] = arbToken;
        setTokens(tokens);
    }

    function want() external view returns (address) {
        return wantToken;
    }

    // puts the funds to work
    function deposit() public whenNotStopped {
        uint256 wantTokenBal = IERC20(wantToken).balanceOf(address(this));

        if (wantTokenBal > 0) {
            IBFRRouter(chef).stakeBfr(wantTokenBal);
            lastDepositTime = block.timestamp;
            emit Deposit(wantTokenBal);
        }
    }

    function withdraw(uint256 _amount) external {
        require(msg.sender == vault, "!vault");
        uint256 wantTokenBal = IERC20(wantToken).balanceOf(address(this));
        if (wantTokenBal < _amount) {
            IBFRRouter(chef).unstakeBfr(_amount - wantTokenBal);
            wantTokenBal = IERC20(wantToken).balanceOf(address(this));
        }

        if (wantTokenBal > _amount) {
            wantTokenBal = _amount;
        }

        IERC20(wantToken).safeTransfer(vault, wantTokenBal);
        emit Withdraw(wantTokenBal);
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
    function _harvest() internal whenNotStopped {
        IBFRRouter(chef).compound();
        // Claim and re-stake esBFR and multiplier points
        IBFRTracker(rewardStorage).claim(address(this));
        uint256 rewardTokenBalance = IERC20(rewardToken).balanceOf(address(this));
        if (rewardTokenBalance > 0) {
            swapRewards();
            chargeFees();
            uint256 wantTokenHarvested = balanceOfWant();
            deposit();
            lastHarvest = block.timestamp;
            emit StratHarvest(msg.sender, wantTokenHarvested, balanceOf());
        }
    }

    // performance fees
    function chargeFees() internal {
        uint256 devFeeAmount = IERC20(wantToken).balanceOf(address(this)) * DEV_FEE / DIVISOR;
        uint256 stakingFeeAmount = IERC20(wantToken).balanceOf(address(this)) * STAKING_FEE / DIVISOR;
        uint256 wantBal = IERC20(wantToken).balanceOf(address(this));
        IERC20(wantToken).safeTransfer(devFeeAddress, devFeeAmount);

        if (stakingFeeAmount > 0) {
            IERC20(wantToken).safeTransfer(stakingAddress, stakingFeeAmount);
        }

        emit ChargedFees(DEV_FEE, devFeeAmount + stakingFeeAmount);
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
        return IBFRTracker(balanceTracker).depositBalances(address(this), wantToken);
    }

    // returns rewards unharvested
    function rewardsAvailable() public view returns (uint256) {
        return IBFRTracker(rewardStorage).claimable(address(this));
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
        IBFRRouter(chef).unstakeBfr(balanceOfPool());
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
        IERC20(rewardToken).safeApprove(unirouter, type(uint).max);
        IERC20(arbToken).safeApprove(unirouter, type(uint).max);
    }

    function _removeAllowances() internal {
        IERC20(wantToken).safeApprove(balanceTracker, 0);
        IERC20(rewardToken).safeApprove(unirouter, 0);
        IERC20(arbToken).safeApprove(unirouter, 0);
    }

    function nativeToWant() external view virtual returns (address[] memory) {}

}

