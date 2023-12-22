// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./IERC20Upgradeable.sol";
import "./ERC20Upgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./SafeERC20Upgradeable.sol";

contract StakingRewardsToken is
    Initializable,
    OwnableUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    ERC20Upgradeable
{
    using SafeERC20Upgradeable for IERC20Upgradeable;

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

    struct StakingInfo {
        uint256 amount;
        uint256 startTime;
        uint256 lockTime;
        uint256 vstLODEAmount;
    }

    mapping(address => StakingInfo) public stakers;

    event StakedLODE(address indexed user, uint256 amount, uint256 lockTime);
    event StakedEsLODE(address indexed user, uint256 amount);
    event UnstakedLODE(address indexed user, uint256 amount);
    event UnstakedEsLODE(address indexed user, uint256 amount);
    event RewardsClaimed(address indexed user, uint256 reward);

    function initialize(
        IERC20Upgradeable _LODE,
        IERC20Upgradeable _wETH,
        IERC20Upgradeable _esLODE
    ) external initializer {
        __Ownable_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        __ERC20_init("Staking LODE", "stLODE");

        LODE = _LODE;
        wETH = _wETH;
        esLODE = _esLODE;

        stLODE3M = 14;
        stLODE6M = 2;
        vstLODE3M = 5;
        vstLODE6M = 10;
    }

    function stakeLODE(uint256 amount) external whenNotPaused nonReentrant {
        _stakeLODE(msg.sender, amount, 0);
    }

    function stakeLODEWithLock(uint256 amount, uint256 lockTime) external whenNotPaused nonReentrant {
        require(lockTime == 90 days || lockTime == 180 days, "StakingRewards: Invalid lock time");
        _stakeLODE(msg.sender, amount, lockTime);
    }

    function _stakeLODE(address staker, uint256 amount, uint256 lockTime) internal {
        require(LODE.transferFrom(staker, address(this), amount), "StakingRewards: Transfer failed");
        if (stakers[staker].amount == 0) {
            stakers[staker].startTime = block.timestamp;
            stakers[staker].lockTime = lockTime;
        }
        stakers[staker].amount += amount;
        totalStaked += amount;
        _mint(staker, amount);
        emit StakedLODE(staker, amount, lockTime);
    }

    function stakeEsLODE(uint256 amount) external whenNotPaused nonReentrant {
        require(esLODE.transferFrom(msg.sender, address(this), amount), "StakingRewards: Transfer failed");
        stakers[msg.sender].amount += amount;
        totalStaked += amount;
        _mint(msg.sender, amount);
        emit StakedEsLODE(msg.sender, amount);
    }

    function relock(uint256 lockTime) external whenNotPaused nonReentrant {
        require(lockTime == 90 days || lockTime == 180 days, "StakingRewards: Invalid lock time");
        StakingInfo storage info = stakers[msg.sender];
        require(info.amount > 0, "StakingRewards: No stake found");
        require(info.startTime + info.lockTime <= block.timestamp, "StakingRewards: Lock time not expired");

        // Calculate vstLODE to mint based on the previous lock period
        uint256 vstLODEAmount;
        if (info.lockTime == 90 days) {
            vstLODEAmount = (info.amount * vstLODE3M) / 100;
        } else if (info.lockTime == 180 days) {
            vstLODEAmount = (info.amount * vstLODE6M) / 100;
        }

        // Update stake with new lock period and mint vstLODE tokens
        info.lockTime = lockTime;
        info.startTime = block.timestamp;
        info.vstLODEAmount += vstLODEAmount;
        totalVstLODE += vstLODEAmount;
        _mint(msg.sender, vstLODEAmount);
    }

    function unstakeLODE(uint256 amount) external nonReentrant {
        require(stakers[msg.sender].amount >= amount, "StakingRewards: Invalid unstake amount");
        require(
            stakers[msg.sender].startTime + stakers[msg.sender].lockTime <= block.timestamp || lockCanceled,
            "StakingRewards: Tokens are still locked"
        );
        _burn(msg.sender, amount);
        stakers[msg.sender].amount -= amount;
        totalStaked -= amount;
        claimRewards();
        LODE.transfer(msg.sender, amount);
        emit UnstakedLODE(msg.sender, amount);
    }

    function unstakeEsLODE(uint256 amount) external nonReentrant {
        require(stakers[msg.sender].amount >= amount, "StakingRewards: Invalid unstake amount");
        _burn(msg.sender, amount);
        stakers[msg.sender].amount -= amount;
        totalStaked -= amount;
        claimRewards();
        esLODE.transfer(msg.sender, amount);
        emit UnstakedEsLODE(msg.sender, amount);
    }

    function claimRewards() public nonReentrant {
        uint256 reward = calculateReward(msg.sender);
        wETH.safeTransfer(msg.sender, reward);
        emit RewardsClaimed(msg.sender, reward);
    }

    function calculateReward(address staker) public view returns (uint256) {
        uint256 timeDiff = block.timestamp - lastUpdateTimestamp;
        uint256 totalReward = (weeklyRewards * timeDiff) / 7 days;
        uint256 stakerBalance = balanceOf(staker);
        uint256 totalBalance = totalSupply();
        uint256 reward = (totalReward * stakerBalance) / totalBalance;
        return reward;
    }

    function getAccountTotalSharePercentage(address account) public view returns (uint256) {
        uint256 totalStakedLODE = totalSupply();
        uint256 accountStaked = balanceOf(account);
        return (accountStaked * 100) / totalStakedLODE;
    }

    function cancelLockPeriod() external onlyOwner {
        lockCanceled = true;
    }

    function recoverERC20(address token) external onlyOwner {
        uint256 balance = IERC20Upgradeable(token).balanceOf(address(this));
        IERC20Upgradeable(token).safeTransfer(owner(), balance);
    }

    function setStLODERate(uint256 rate3M, uint256 rate6M) external onlyOwner {
        stLODE3M = rate3M;
        stLODE6M = rate6M;
    }

    function setVstLODERate(uint256 rate3M, uint256 rate6M) external onlyOwner {
        vstLODE3M = rate3M;
        vstLODE6M = rate6M;
    }

    function setWeeklyRewards(uint256 rewards) external onlyOwner {
        weeklyRewards = rewards;
        lastUpdateTimestamp = block.timestamp;
    }
}

