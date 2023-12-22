// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./ERC20.sol";
import "./SafeERC20.sol";
import "./StratFeeManager.sol";
import "./GasFeeThrottler.sol";
import "./ICapETHPool.sol";
import "./ICapRewards.sol";
import "./Manager.sol";
import "./PausableTimed.sol";
import "./Stoppable.sol";

contract CapEthPoolStrategy is Manager, PausableTimed, GasFeeThrottler, Stoppable {
    using SafeERC20 for IERC20;

    address public vault;
    address public pool;
    address public rewards;
    address public stakingAddress;
    address public devFeeAddress;
    uint256 constant DIVISOR = 1 ether;
    uint256 DEV_FEE = 5 * 10 ** 16;
    uint256 STAKING_FEE = 0;
    uint256 MAX_FEE = 5 * 10 ** 17;

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
        address _rewards
    ) {
        vault = _vault;
        pool = _pool;
        rewards = _rewards;
        devFeeAddress = _msgSender();
    }

    receive() external payable {}
    fallback() external payable {}

    function deposit() public payable whenNotStopped {
        if (paused()) {
            emit PendingDeposit(balanceOf());
            return;
        }
        if (address(this).balance > 0) {
            ICapETHPool(pool).deposit{value : address(this).balance}(0);
            lastPoolDepositTime = block.timestamp;
            emit Deposit(balanceOf());
        }
    }

    function _withdraw(uint256 _amount) internal {
        require(msg.sender == vault, "!vault");
        uint256 wantTokenBal = address(this).balance;

        if (wantTokenBal < _amount) {
            ICapETHPool(pool).withdraw(_amount - wantTokenBal);
            wantTokenBal = address(this).balance;
        }

        if (wantTokenBal > _amount) {
            wantTokenBal = _amount;
        }

        (bool success,) = vault.call{value : wantTokenBal}('');
        require(success, "WITHDRAW_FAILED");
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
        uint256 tokenBal = address(this).balance;
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
        uint256 devFeeAmount = address(this).balance * DEV_FEE / DIVISOR;
        uint256 stakingFeeAmount = address(this).balance * STAKING_FEE / DIVISOR;
        (bool devFeeTransferSuccess,) = devFeeAddress.call{value : devFeeAmount}('');
        require(devFeeTransferSuccess, "DEV_FEE_TRANSFER_FAILED");

        if (stakingFeeAmount > 0) {
            (bool protocolTransferSuccess,) = stakingAddress.call{value : stakingFeeAmount}('');
            require(protocolTransferSuccess, "PROTOCOL_TOKEN_FEE_TRANSFER_FAILED");
        }

        emit ChargedFees(DEV_FEE, devFeeAmount + stakingFeeAmount);
    }

    // calculate the total underlying 'wantToken' held by the strat.
    function balanceOf() public view returns (uint256) {
        return balanceOfWant() + balanceOfPool();
    }

    // it calculates how much 'wantToken' this contract holds.
    function balanceOfWant() public view returns (uint256) {
        return address(this).balance;
    }

    // it calculates how much 'wantToken' the strategy has working in the farm.
    function balanceOfPool() public view returns (uint256) {
        return ICapETHPool(pool).getCurrencyBalance(address(this));
    }

    // returns rewards unharvested
    function rewardsAvailable() public view returns (uint256) {
        return ICapRewards(rewards).getClaimableReward();
    }

    // native reward amount for calling harvest
    // function callReward() public view returns (uint256) {}
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
        pause();
        ICapRewards(rewards).collectReward();
        ICapETHPool(pool).withdraw(balanceOfPool());
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
    }

    function resume() public onlyOwner {
        _resume();
        deposit();
    }

}

