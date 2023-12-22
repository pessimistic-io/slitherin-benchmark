// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./IERC20Upgradeable.sol";
import "./ERC20Upgradeable.sol";
import "./ContextUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./SafeERC20Upgradeable.sol";

contract StakingRewardsToken is
    Initializable,
    ContextUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    ERC20Upgradeable
{
    using SafeERC20Upgradeable for IERC20Upgradeable;

    address private _owner;
    address private _newOwner;
    address private _routerContract;

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

    uint256[50] private __gap;

    event StakedLODE(address indexed user, uint256 amount, uint256 lockTime);
    event StakedEsLODE(address indexed user, uint256 amount);
    event UnstakedLODE(address indexed user, uint256 amount);
    event UnstakedEsLODE(address indexed user, uint256 amount);
    event RewardsClaimed(address indexed user, uint256 reward);
    event WeeklyRewardsUpdated(uint256 newRewards);
    event RouterContractUpdated(address routerContract);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event StakingLockedCanceled();
    event StakingPaused();
    event StakingUnpaused();
    event StakingRatesUpdated(uint256 stLODE3M, uint256 stLODE6M, uint256 vstLODE3M, uint256 vstLODE6M);
    event Relocked(address indexed user, uint256 indexed lockTime, uint256 indexed esLODEAmount);

    modifier onlyOwner() {
        require(_msgSender() == _owner, "Ownable: caller is not the owner");
        _;
    }

    modifier onlyRouterContract() {
        require(_msgSender() == _routerContract, "StakingRewards: caller is not the router contract");
        _;
    }

    function initialize(
        IERC20Upgradeable _LODE,
        IERC20Upgradeable _wETH,
        IERC20Upgradeable _esLODE,
        address initialRouterContract
    ) public initializer {
        __Context_init_unchained();
        __Pausable_init_unchained();
        __ReentrancyGuard_init_unchained();
        __ERC20_init("Staking LODE", "stLODE");

        LODE = _LODE;
        wETH = _wETH;
        esLODE = _esLODE;

        weeklyRewards = 0;
        lastUpdateTimestamp = block.timestamp;
        totalStaked = 0;
        totalVstLODE = 0;
        stLODE3M = 14000000000000000000;
        stLODE6M = 2000000000000000000;
        vstLODE3M = 5000000000000000000;
        vstLODE6M = 10000000000000000000;

        lockCanceled = false;

        _owner = _msgSender();
        _routerContract = initialRouterContract;

        emit OwnershipTransferred(address(0), _owner);
        emit RouterContractUpdated(initialRouterContract);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        _newOwner = newOwner;
    }

    function acceptOwnership() external {
        require(_msgSender() == _newOwner, "Ownable: caller is not the new owner");
        emit OwnershipTransferred(_owner, _newOwner);
        _owner = _newOwner;
        _newOwner = address(0);
    }

    function updateRouterContract(address routerContract) external onlyOwner {
        require(routerContract != address(0), "StakingRewards: router contract cannot be the zero address");
        _routerContract = routerContract;
        emit RouterContractUpdated(routerContract);
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
        emit Relocked(_msgSender(), lockTime, vstLODEAmount);
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

    function claimRewards() external nonReentrant {
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

    function updateRewards(uint256 newRewards) external onlyRouterContract {
        weeklyRewards = newRewards;
        lastUpdateTimestamp = block.timestamp;
        emit WeeklyRewardsUpdated(newRewards);
    }

    function setStakingRates(
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

    function getRouterContract() external view returns (address) {
        return _routerContract;
    }

    function getOwner() external view returns (address) {
        return _owner;
    }
}

