// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./IERC20Upgradeable.sol";
import "./ERC20Upgradeable.sol";
import "./ContextUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./Ownable2StepUpgradeable.sol";

contract StakingRewardsToken is
    Initializable,
    ContextUpgradeable,
    Ownable2StepUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    ERC20Upgradeable
{
    using SafeERC20Upgradeable for IERC20Upgradeable;

    struct Stake {
        uint256 amount;
        uint256 startTimestamp;
    }

    struct StakingInfo {
        uint256 lodeAmount;
        uint256 stLODEAmount;
        uint256 startTime;
        uint256 lockTime;
        uint256 vstLODEAmount;
        mapping(uint256 => Stake) esLODEStakes;
        uint256 nextStakeId;
        uint256 totalEsLODEStakedByUser;
    }

    mapping(address => StakingInfo) public stakers;

    IERC20Upgradeable public LODE;
    IERC20Upgradeable public wETH;
    IERC20Upgradeable public esLODE;

    uint256 public weeklyRewards;
    uint256 public lastUpdateTimestamp;
    uint256 public totalStaked;
    uint256 public totalVstLODE;
    uint256 public stLODE3M;
    uint256 public stLODE6M;
    uint256 public vstLODE3M;
    uint256 public vstLODE6M;

    bool public lockCanceled;
    bool public withdrawEsLODEAllowed;
    address public routerContract;

    uint256[50] private __gap;

    event StakedLODE(address indexed user, uint256 amount, uint256 lockTime);
    event StakedEsLODE(address indexed user, uint256 amount);
    event UnstakedLODE(address indexed user, uint256 amount);
    event UnstakedEsLODE(address indexed user, uint256 amount);
    event RewardsClaimed(address indexed user, uint256 reward);
    event StakingLockedCanceled();
    event WeeklyRewardsUpdated(uint256 newRewards);
    event StakingRatesUpdated(uint256 stLODE3M, uint256 stLODE6M, uint256 vstLODE3M, uint256 vstLODE6M);
    event StakingPaused();
    event StakingUnpaused();
    event RouterContractUpdated(address newRouterContract);
    event esLODEUnlocked(bool state, uint256 timestamp);

    function initialize(address _LODE, address _wETH, address _esLODE, address _routerContract) public initializer {
        __Context_init();
        __Ownable2Step_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        __ERC20_init("Staking LODE", "stLODE");

        LODE = IERC20Upgradeable(_LODE);
        wETH = IERC20Upgradeable(_wETH);
        esLODE = IERC20Upgradeable(_esLODE);
        routerContract = _routerContract;

        stLODE3M = 1400000000000000000;
        stLODE6M = 2000000000000000000;
        vstLODE3M = 50000000000000000;
        vstLODE6M = 100000000000000000;
    }

    function stakeLODE(uint256 amount, uint256 lockTime) external whenNotPaused nonReentrant {
        require(
            lockTime == 10 seconds || lockTime == 90 days || lockTime == 180 days,
            "StakingRewards: Invalid lock time"
        );
        stakeLODEInternal(msg.sender, amount, lockTime);
    }

    function stakeLODEInternal(address staker, uint256 amount, uint256 lockTime) internal {
        require(LODE.transferFrom(staker, address(this), amount), "StakingRewards: Transfer failed");

        uint256 mintAmount = amount;

        if (lockTime == 90 days) {
            mintAmount = (amount * stLODE3M) / 1e18; // Scale the mint amount for 3 months lock time
        } else if (lockTime == 180 days) {
            mintAmount = (amount * stLODE6M) / 1e18; // Scale the mint amount for 6 months lock time
        }

        if (stakers[staker].lodeAmount == 0 && stakers[staker].stLODEAmount == 0) {
            stakers[staker].startTime = block.timestamp;
            stakers[staker].lockTime = lockTime;
        }
        stakers[staker].lodeAmount += amount; // Update LODE staked amount
        stakers[staker].stLODEAmount += mintAmount; // Update stLODE minted amount
        stakers[staker].totalEsLODEStakedByUser += amount; // Update total EsLODE staked by user
        totalStaked += amount;
        _mint(staker, mintAmount);
        emit StakedLODE(staker, amount, lockTime);
    }

    function stakeEsLODE(uint256 amount) external whenNotPaused nonReentrant {
        require(esLODE.transferFrom(msg.sender, address(this), amount), "StakingRewards: Transfer failed");
        stakeEsLODEInternal(amount);
    }

    function stakeEsLODEInternal(uint256 amount) internal {
        require(amount > 0, "StakingRewards: Invalid amount");
        require(esLODE.balanceOf(msg.sender) >= amount, "StakingRewards: Insufficient balance");

        stakers[msg.sender].esLODEStakes[stakers[msg.sender].nextStakeId++] = Stake({
            amount: amount,
            startTimestamp: block.timestamp
        });

        stakers[msg.sender].totalEsLODEStakedByUser += amount; // Update total EsLODE staked by user
        totalStaked += amount;
        _mint(msg.sender, amount);
        emit StakedEsLODE(msg.sender, amount);
    }

    function convertEsLODEToLODE(address user) internal {
        uint256 totalDays = 365;

        for (uint256 i = 0; i < stakers[user].nextStakeId; ++i) {
            uint256 elapsedDays = (block.timestamp - stakers[user].esLODEStakes[i].startTimestamp) / 1 days;

            if (elapsedDays >= totalDays) {
                stakers[user].lodeAmount += stakers[user].esLODEStakes[i].amount;
                esLODE.transfer(address(0), stakers[user].esLODEStakes[i].amount);
                stakers[user].esLODEStakes[i].amount = 0;
            } else {
                uint256 convertedAmount = (stakers[user].esLODEStakes[i].amount * elapsedDays) / totalDays;
                uint256 burntAmount = stakers[user].esLODEStakes[i].amount - convertedAmount;
                stakers[user].lodeAmount += convertedAmount;
                esLODE.transfer(address(0), burntAmount);
                stakers[user].esLODEStakes[i].amount = convertedAmount;
            }
        }
    }

    function relock(uint256 lockTime) external whenNotPaused nonReentrant {
        require(lockTime == 90 days || lockTime == 180 days, "StakingRewards: Invalid lock time");
        StakingInfo storage info = stakers[msg.sender];
        require(info.lodeAmount > 0, "StakingRewards: No stake found");
        require(info.startTime + info.lockTime <= block.timestamp, "StakingRewards: Lock time not expired");

        convertEsLODEToLODE(msg.sender);

        // Calculate vstLODE to mint based on the previous lock period
        uint256 vstLODEAmount;
        if (info.lockTime == 90 days) {
            vstLODEAmount = (info.lodeAmount * vstLODE3M) / 1e18;
        } else if (info.lockTime == 180 days) {
            vstLODEAmount = (info.lodeAmount * vstLODE6M) / 1e18;
        }

        // Update stake with new lock period and mint vstLODE tokens
        info.lockTime = lockTime;
        info.startTime = block.timestamp;
        info.vstLODEAmount += vstLODEAmount;
        totalVstLODE += vstLODEAmount;
        _mint(msg.sender, vstLODEAmount);
    }

    function unstakeLODE(uint256 amount) external nonReentrant {
        require(stakers[msg.sender].lodeAmount >= amount, "StakingRewards: Invalid unstake amount");
        require(
            stakers[msg.sender].startTime + stakers[msg.sender].lockTime <= block.timestamp,
            "StakingRewards: Tokens are still locked"
        );

        convertEsLODEToLODE(msg.sender);

        unstakeLODEInternal(msg.sender, amount);
    }

    function withdrawEsLODE() external nonReentrant {
        require(withdrawEsLODEAllowed == true, "esLODE Withdrawals Not Permitted");
        claimRewardsInternal();
        StakingInfo storage account = stakers[msg.sender];
        uint256 totalEsLODE = account.totalEsLODEStakedByUser;
        esLODE.safeTransfer(msg.sender, totalEsLODE);
    }

    function unstakeLODEInternal(address user, uint256 amount) internal {
        claimRewardsInternal();

        _burn(user, amount);
        stakers[user].lodeAmount -= amount;
        stakers[user].totalEsLODEStakedByUser -= amount; // Update total EsLODE staked by user
        totalStaked -= amount;
        LODE.transfer(user, amount);
        emit UnstakedLODE(user, amount);
    }

    function unstakeEsLODEInternal(address user, uint256 amount) internal {
        claimRewardsInternal();

        _burn(user, amount);
        stakers[user].totalEsLODEStakedByUser -= amount; // Update total EsLODE staked by user
        totalStaked -= amount;
        esLODE.transfer(user, amount);
        emit UnstakedEsLODE(user, amount);
    }

    function claimRewards() public nonReentrant {
        claimRewardsInternal();
    }

    function claimRewardsInternal() internal {
        uint256 reward = calculateReward(msg.sender);
        wETH.safeTransfer(msg.sender, reward);
        emit RewardsClaimed(msg.sender, reward);
    }

    function calculateReward(address staker) public view returns (uint256) {
        uint256 timeDiff = block.timestamp - lastUpdateTimestamp;
        uint256 totalReward = (weeklyRewards * timeDiff) / 7 days;
        uint256 stakerBalance = balanceOf(staker) + stakers[staker].vstLODEAmount;
        uint256 totalBalance = totalSupply() + totalVstLODE;
        uint256 reward = (totalReward * stakerBalance) / totalBalance;
        return reward;
    }

    function updateWeeklyRewards(uint256 _weeklyRewards) external {
        require(msg.sender == routerContract, "StakingRewards: Unauthorized");
        weeklyRewards = _weeklyRewards;
        lastUpdateTimestamp = block.timestamp;
        emit WeeklyRewardsUpdated(_weeklyRewards);
    }

    function getTotalEsLODEStaked() external view returns (uint256) {
        return totalStaked;
    }

    function getTotalEsLODEStakedByUser(address user) external view returns (uint256) {
        return stakers[user].totalEsLODEStakedByUser;
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal override whenNotPaused {
        super._beforeTokenTransfer(from, to, amount);
    }

    // Helper function to calculate the vote share of a user
    function accountVoteShare(address account) public view returns (uint256) {
        uint256 stLODEStaked = stakers[account].stLODEAmount;
        uint256 vstLODEStaked = stakers[account].vstLODEAmount;
        uint256 totalStLODEStaked = totalSupply() - totalVstLODE;
        uint256 totalVstLODEStaked = totalVstLODE;

        uint256 totalStakedAmount = stLODEStaked + vstLODEStaked;
        uint256 totalStakedBalance = totalStLODEStaked + totalVstLODEStaked;

        if (totalStakedBalance == 0) {
            return 0;
        }

        return (totalStakedAmount * 1e18) / totalStakedBalance;
    }

    /* **ADMIN FUNCTIONS** */

    function _pauseStaking() external onlyOwner {
        _pause();
        emit StakingPaused();
    }

    function _unpauseStaking() external onlyOwner {
        _unpause();
        emit StakingUnpaused();
    }

    function _updateRouterContract(address _routerContract) external onlyOwner {
        routerContract = _routerContract;
        emit RouterContractUpdated(_routerContract);
    }

    function _cancelLock() external onlyOwner {
        lockCanceled = true;
        emit StakingLockedCanceled();
    }

    function _allowEsLODEWithdraw(bool state) external onlyOwner {
        withdrawEsLODEAllowed = state;
        emit esLODEUnlocked(state, block.timestamp);
    }
}

