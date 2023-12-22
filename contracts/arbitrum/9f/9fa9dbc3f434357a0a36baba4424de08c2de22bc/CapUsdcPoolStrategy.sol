pragma solidity ^0.8.0;

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./ERC20.sol";
import "./SafeERC20.sol";
import "./StratFeeManager.sol";
import "./GasFeeThrottler.sol";
import "./ICapPool.sol";
import "./ICapRewards.sol";
import "./Manager.sol";
import "./PausableTimed.sol";
import "./Stoppable.sol";

contract CapUsdcPoolStrategy is Manager, PausableTimed, GasFeeThrottler, Stoppable {
    using SafeERC20 for IERC20;

    address public token;
    address public pool;
    address public vault;
    address public rewards;
    address public stakingAddress;
    address public devFeeAddress;

    uint256 DIVISOR;
    uint256 CAP_MULTIPLIER = 10 ** 12;

    uint256 public DEV_FEE;
    uint256 STAKING_FEE = 0;
    uint MAX_FEE;

    uint256 public lastPoolDepositTime;
    bool public harvestOnDeposit;
    uint256 public lastHarvest;

    event StratHarvest(address indexed harvester, uint256 wantTokenHarvested, uint256 tvl);
    event Deposit(uint256 tvl);
    event PendingDeposit(uint256 totalPending);
    event Withdraw(uint256 tvl);
    event ChargedFees(uint256 fees, uint256 amount);

    constructor(
        address _vault,
        address _pool,
        address _rewards,
        address _token
    ) {
        vault = _vault;
        pool = _pool;
        rewards = _rewards;
        token = _token;
        _giveAllowances();
        DEV_FEE = 5 * 10 ** (ERC20(token).decimals() - 2);
        MAX_FEE = 5 * 10 ** (ERC20(token).decimals() - 1);
        DIVISOR = 10 ** ERC20(token).decimals();
        devFeeAddress = _msgSender();
    }


    function want() external view returns (address) {
        return token;
    }

    // puts the funds to work
    function deposit() public whenNotStopped {
        if (paused()) {
            emit PendingDeposit(balanceOf());
            return;
        }
        uint256 tokenBalance = IERC20(token).balanceOf(address(this));
        if (tokenBalance > 0) {
            ICapPool(pool).deposit(tokenBalance * CAP_MULTIPLIER);
            lastPoolDepositTime = block.timestamp;
            emit Deposit(balanceOf());
        }
    }

    function _withdraw(uint256 _amount) internal {
        require(msg.sender == vault, "!vault");
        uint256 wantTokenBal = IERC20(token).balanceOf(address(this));

        if (wantTokenBal < _amount) {
            uint256 amountToWithdraw = (_amount - wantTokenBal) * CAP_MULTIPLIER;
            ICapPool(pool).withdraw(amountToWithdraw);
            wantTokenBal = IERC20(token).balanceOf(address(this));
        }

        if (wantTokenBal > _amount) {
            wantTokenBal = _amount;
        }

        IERC20(token).safeTransfer(vault, wantTokenBal);
        emit Withdraw(balanceOf());
    }

    function withdraw(uint256 _amount) external {
        _withdraw(_amount);
    }

    function beforeDeposit() external virtual {
        if (harvestOnDeposit && !paused()) {
            require(msg.sender == vault, "!vault");
            _harvest();
        }
    }

    function harvest() external gasThrottle virtual {
        _harvest();
    }

    // compounds earnings and charges performance fee
    function _harvest() internal whenNotPaused whenNotStopped {
        ICapRewards(rewards).collectReward();
        uint256 tokenBal = IERC20(token).balanceOf(address(this));
        if (tokenBal > 0) {
            chargeFees();
            uint256 wantTokenHarvested = balanceOfWant();
            deposit();
            lastHarvest = block.timestamp;
            emit StratHarvest(msg.sender, wantTokenHarvested, balanceOf());
        }
    }

    // performance fees
    function chargeFees() internal {
        uint256 devFeeAmount = IERC20(token).balanceOf(address(this)) * DEV_FEE / DIVISOR;
        uint256 stakingFeeAmount = IERC20(token).balanceOf(address(this)) * STAKING_FEE / DIVISOR;
        IERC20(token).safeTransfer(devFeeAddress, devFeeAmount);

        if (stakingFeeAmount > 0) {
            IERC20(token).safeTransfer(stakingAddress, stakingFeeAmount);
        }

        emit ChargedFees(DEV_FEE, devFeeAmount + stakingFeeAmount);
    }

    // calculate the total underlying 'wantToken' held by the strat.
    function balanceOf() public view returns (uint256) {
        return balanceOfWant() + balanceOfPool();
    }

    // it calculates how much 'wantToken' this contract holds.
    function balanceOfWant() public view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }

    // it calculates how much 'wantToken' the strategy has working in the farm.
    function balanceOfPool() public view returns (uint256) {
        uint256 capPoolAmount = ICapPool(pool).getCurrencyBalance(address(this));
        return capPoolAmount / CAP_MULTIPLIER;
    }

    // returns rewards unharvested
    function rewardsAvailable() public view returns (uint256) {
        return ICapRewards(rewards).getClaimableReward();
    }


    function setHarvestOnDeposit(bool _harvestOnDeposit) external onlyManagerAndOwner {
        harvestOnDeposit = _harvestOnDeposit;
    }

    function setDevFee(uint fee) external onlyManagerAndOwner {
        require(fee + STAKING_FEE <= MAX_FEE, "fee too high");
        DEV_FEE = fee;
    }

    function setStakingFee(uint fee) external onlyManagerAndOwner {
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

    // pauses deposits and withdraws all funds from third party systems.
    function panic() public onlyOwner {
        stop();
        ICapRewards(rewards).collectReward();
        ICapPool(pool).withdraw(balanceOfPool());
    }

    function pause() public onlyManagerAndOwner {
        _harvest();
        _pause();
    }

    function unpause() external onlyManagerAndOwner {
        _unpause();
        deposit();
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

    function _giveAllowances() internal {
        IERC20(token).safeApprove(pool, type(uint).max);
    }

    function _removeAllowances() internal {
        IERC20(token).safeApprove(pool, 0);
    }
}

