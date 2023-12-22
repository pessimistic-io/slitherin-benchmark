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

    struct StakingInfo {
        uint256 amount;
        uint256 startTime;
        uint256 lockTime;
        uint256 vstLODEAmount;
        uint256 esLODEAmount;
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

        stLODE3M = 14000000000000000000;
        stLODE6M = 2000000000000000000;
        vstLODE3M = 5000000000000000000;
        vstLODE6M = 10000000000000000000;
    }

    function stakeLODE(uint256 amount) external whenNotPaused nonReentrant {
        stakeLODEInternal(_msgSender(), amount, 0);
    }

    function stakeLODEWithLock(uint256 amount, uint256 lockTime) external whenNotPaused nonReentrant {
        require(lockTime == 90 days || lockTime == 180 days, "StakingRewards: Invalid lock time");
        stakeLODEInternal(_msgSender(), amount, lockTime);
    }

    function stakeLODEInternal(address staker, uint256 amount, uint256 lockTime) internal {
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
        require(esLODE.transferFrom(_msgSender(), address(this), amount), "StakingRewards: Transfer failed");
        stakers[_msgSender()].amount += amount;
        totalStaked += amount;
        _mint(_msgSender(), amount);
        emit StakedEsLODE(_msgSender(), amount);
    }

    function relock(uint256 lockTime) external whenNotPaused nonReentrant {
        require(lockTime == 90 days || lockTime == 180 days, "StakingRewards: Invalid lock time");
        StakingInfo storage info = stakers[_msgSender()];
        require(info.amount > 0, "StakingRewards: No stake found");
        require(info.startTime + info.lockTime <= block.timestamp, "StakingRewards: Lock time not expired");

        // Calculate vstLODE to mint based on the previous lock period
        uint256 vstLODEAmount;
        if (info.lockTime == 90 days) {
            vstLODEAmount = (info.amount * vstLODE3M) / 1e18;
        } else if (info.lockTime == 180 days) {
            vstLODEAmount = (info.amount * vstLODE6M) / 1e18;
        }

        // Update stake with new lock period and mint vstLODE tokens
        info.lockTime = lockTime;
        info.startTime = block.timestamp;
        info.vstLODEAmount += vstLODEAmount;
        totalVstLODE += vstLODEAmount;
        _mint(_msgSender(), vstLODEAmount);
    }

    function unstakeLODE(uint256 amount) external nonReentrant {
        uint256 reward = calculateReward(_msgSender());
        require(reward == 0, "StakingRewards: Please claim rewards before unstaking");
        unstakeLODEInternal(_msgSender(), amount);
    }

    function unstakeEsLODE(uint256 amount) external nonReentrant {
        uint256 reward = calculateReward(_msgSender());
        require(reward == 0, "StakingRewards: Please claim rewards before unstaking");
        unstakeEsLODEInternal(_msgSender(), amount);
    }

    function unstakeLODEInternal(address user, uint256 amount) internal {
        require(stakers[user].amount >= amount, "StakingRewards: Invalid unstake amount");
        require(
            stakers[user].startTime + stakers[user].lockTime <= block.timestamp || lockCanceled,
            "StakingRewards: Tokens are still locked"
        );
        _burn(user, amount);
        stakers[user].amount -= amount;
        totalStaked -= amount;
        LODE.transfer(user, amount);
        emit UnstakedLODE(user, amount);
    }

    function unstakeEsLODEInternal(address user, uint256 amount) internal {
        require(stakers[user].amount >= amount, "StakingRewards: Invalid unstake amount");
        _burn(user, amount);
        stakers[user].amount -= amount;
        totalStaked -= amount;
        esLODE.transfer(user, amount);
        emit UnstakedEsLODE(user, amount);
    }

    function claimRewards() public nonReentrant {
        uint256 reward = calculateReward(_msgSender());
        wETH.safeTransfer(_msgSender(), reward);
        emit RewardsClaimed(_msgSender(), reward);
    }

    function calculateReward(address staker) public view returns (uint256) {
        uint256 timeDiff = block.timestamp - lastUpdateTimestamp;
        uint256 totalReward = (weeklyRewards * timeDiff) / 7 days;
        uint256 stakerBalance = balanceOf(staker);
        uint256 totalBalance = totalSupply();
        uint256 reward = (totalReward * stakerBalance) / totalBalance;
        return reward;
    }

    function cancelLock() external onlyOwner {
        lockCanceled = true;
        emit StakingLockedCanceled();
    }

    function updateWeeklyRewards(uint256 _weeklyRewards) external onlyOwner {
        weeklyRewards = _weeklyRewards;
        lastUpdateTimestamp = block.timestamp;
        emit WeeklyRewardsUpdated(_weeklyRewards);
    }

    function updateStakingRates(
        uint256 _stLODE3M,
        uint256 _stLODE6M,
        uint256 _vstLODE3M,
        uint256 _vstLODE6M
    ) external onlyOwner {
        stLODE3M = _stLODE3M;
        stLODE6M = _stLODE6M;
        vstLODE3M = _vstLODE3M;
        vstLODE6M = _vstLODE6M;
        emit StakingRatesUpdated(_stLODE3M, _stLODE6M, _vstLODE3M, _vstLODE6M);
    }

    function pauseStaking() external onlyOwner {
        _pause();
        emit StakingPaused();
    }

    function unpauseStaking() external onlyOwner {
        _unpause();
        emit StakingUnpaused();
    }

    function updateRouterContract(address _routerContract) external onlyOwner {
        routerContract = _routerContract;
        emit RouterContractUpdated(_routerContract);
    }

    function getStakedAmounts(
        address account
    ) external view returns (uint256 stLODEAmount, uint256 vstLODEAmount, uint256 esLODEAmount) {
        StakingInfo memory stakingInfo = stakers[account];
        return (stakingInfo.amount, stakingInfo.vstLODEAmount, stakingInfo.esLODEAmount);
    }

    function getTotalEsLODEStaked() external view returns (uint256) {
        return totalStaked;
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal override whenNotPaused {
        super._beforeTokenTransfer(from, to, amount);
    }
}

