// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

// Interfaces
import { IERC20 } from "./IERC20.sol";

// Libraries
import { Math } from "./Math.sol";
import { SafeMath } from "./SafeMath.sol";
import { SafeERC20 } from "./SafeERC20.sol";

// Contracts
import { ReentrancyGuard } from "./ReentrancyGuard.sol";
import { Ownable } from "./Ownable.sol";
import { Pausable } from "./Pausable.sol";
import { ContractWhitelist } from "./ContractWhitelist.sol";

contract StakingRewardsV3 is
  ReentrancyGuard,
  Ownable,
  Pausable,
  ContractWhitelist
{
  using SafeMath for uint256;
  using SafeERC20 for IERC20;

  /* ========== STATE VARIABLES ========== */

  IERC20 public rewardToken;
  IERC20 public stakingToken;

  uint256 public boost;
  uint256 public periodFinish;
  uint256 public boostedFinish;
  uint256 public rewardRate;
  uint256 public rewardDuration;
  uint256 public lastUpdateTime;
  uint256 public rewardPerTokenStored;
  uint256 public boostedTimePeriod;

  uint256 private _totalSupply;

  mapping(address => uint256) public userRewardPerTokenPaid;
  mapping(address => uint256) public rewardEarned;

  mapping(address => uint256) private _balances;

  /* ========== CONSTRUCTOR ========== */

  constructor(
    address _rewardToken,
    address _stakingToken,
    uint256 _rewardsDuration,
    uint256 _boostedTimePeriod,
    uint256 _boost
  ) {
    rewardToken = IERC20(_rewardToken);
    stakingToken = IERC20(_stakingToken);
    rewardDuration = _rewardsDuration;
    boostedTimePeriod = _boostedTimePeriod;
    boost = _boost;
  }

  /* ========== VIEWS ========== */

  /// @notice Returns the total balance of the staking token in the contract
  function totalSupply() external view returns (uint256) {
    return _totalSupply;
  }

  /// @notice Returns a users deposit of the staking token in the contract
  /// @param account address of the account
  function balanceOf(address account) external view returns (uint256) {
    return _balances[account];
  }

  /// @notice Returns the last time when a reward was applicable
  function lastTimeRewardApplicable() public view returns (uint256) {
    uint256 timeApp = Math.min(block.timestamp, periodFinish);
    return timeApp;
  }

  /// @notice Returns the reward per staking token
  function rewardPerToken() public view returns (uint256 perTokenRate) {
    if (_totalSupply == 0) {
      perTokenRate = rewardPerTokenStored;
      return perTokenRate;
    }
    if (block.timestamp < boostedFinish) {
      perTokenRate = rewardPerTokenStored.add(
        lastTimeRewardApplicable()
          .sub(lastUpdateTime)
          .mul(rewardRate.mul(boost))
          .mul(1e18)
          .div(_totalSupply)
      );
      return perTokenRate;
    } else {
      if (lastUpdateTime < boostedFinish) {
        perTokenRate = rewardPerTokenStored
          .add(
            boostedFinish
              .sub(lastUpdateTime)
              .mul(rewardRate.mul(boost))
              .mul(1e18)
              .div(_totalSupply)
          )
          .add(
            lastTimeRewardApplicable()
              .sub(boostedFinish)
              .mul(rewardRate)
              .mul(1e18)
              .div(_totalSupply)
          );
        return perTokenRate;
      } else {
        perTokenRate = rewardPerTokenStored.add(
          lastTimeRewardApplicable()
            .sub(lastUpdateTime)
            .mul(rewardRate)
            .mul(1e18)
            .div(_totalSupply)
        );
        return perTokenRate;
      }
    }
  }

  /// @notice Returns the amount of rewards earned by an account
  /// @param account address of the account
  function earned(address account) public view returns (uint256 tokensEarned) {
    uint256 perTokenRate = rewardPerToken();
    tokensEarned = _balances[account]
      .mul(perTokenRate.sub(userRewardPerTokenPaid[account]))
      .div(1e18)
      .add(rewardEarned[account]);
  }

  /* ========== MUTATIVE FUNCTIONS ========== */

  /// @notice Allows to stake the staking token into the contract for rewards
  /// @param amount amount of staking token to stake
  function stake(uint256 amount)
    external
    whenNotPaused
    nonReentrant
    updateReward(msg.sender)
  {
    _isEligibleSender();
    require(amount > 0, "Cannot stake 0");
    _totalSupply = _totalSupply.add(amount);
    _balances[msg.sender] = _balances[msg.sender].add(amount);
    stakingToken.safeTransferFrom(msg.sender, address(this), amount);
    emit Staked(msg.sender, amount);
  }

  /// @notice Allows to unstake the staking token from the contract
  /// @param amount amount of staking token to unstake
  function unstake(uint256 amount)
    public
    whenNotPaused
    nonReentrant
    updateReward(msg.sender)
  {
    _isEligibleSender();
    require(amount > 0, "Cannot withdraw 0");
    require(amount <= _balances[msg.sender], "Insufficent balance");
    _totalSupply = _totalSupply.sub(amount);
    _balances[msg.sender] = _balances[msg.sender].sub(amount);
    stakingToken.safeTransfer(msg.sender, amount);
    emit Unstaked(msg.sender, amount);
  }

  /// @notice Allows to claim rewards from the contract for staking
  function claim() public whenNotPaused nonReentrant updateReward(msg.sender) {
    _isEligibleSender();
    uint256 _rewardEarned = rewardEarned[msg.sender];
    if (_rewardEarned > 0) {
      rewardEarned[msg.sender] = 0;
      rewardToken.safeTransfer(msg.sender, _rewardEarned);
    }

    emit RewardPaid(msg.sender, _rewardEarned);
  }

  /// @notice Allows to exit the contract by unstaking all staked tokens and claiming rewards
  function exit() external whenNotPaused nonReentrant {
    unstake(_balances[msg.sender]);
    claim();
  }

  /* ========== RESTRICTED FUNCTIONS ========== */

  /// @notice Transfers all funds to msg.sender
  /// @dev Can only be called by the owner
  /// @param tokens The list of erc20 tokens to withdraw
  /// @param transferNative Whether should transfer the native currency
  function emergencyWithdraw(address[] calldata tokens, bool transferNative)
    external
    onlyOwner
    whenPaused
    returns (bool)
  {
    if (transferNative) payable(msg.sender).transfer(address(this).balance);

    IERC20 token;

    for (uint256 i = 0; i < tokens.length; i++) {
      token = IERC20(tokens[i]);
      token.safeTransfer(msg.sender, token.balanceOf(address(this)));
    }

    emit EmergencyWithdraw(msg.sender);

    return true;
  }

  /// @notice Ends the current rewards
  /// @dev Can only be called by the owner
  function endRewards() public onlyOwner returns (uint256) {
    uint256 _rewards = rewardToken.balanceOf(address(this));
    if (stakingToken == rewardToken) {
      _rewards = _rewards.sub(_totalSupply);
    }
    periodFinish = block.timestamp;
    IERC20(rewardToken).safeTransfer(msg.sender, _rewards);
    return _rewards;
  }

  /// @notice Start a new reward period by sending rewards
  /// @dev Can only be called by the owner
  /// @param rewardAmount the amount of rewards to be distributed
  function notifyRewardAmount(uint256 rewardAmount) external onlyOwner {
    rewardToken.safeTransferFrom(msg.sender, address(this), rewardAmount);

    if (block.timestamp >= periodFinish) {
      rewardRate = rewardAmount.div(rewardDuration.add(boostedTimePeriod));
      boostedFinish = block.timestamp.add(boostedTimePeriod);
    } else {
      uint256 remaining = periodFinish.sub(block.timestamp);
      uint256 leftoverReward = remaining.mul(rewardRate);
      rewardRate = rewardAmount.add(leftoverReward).div(rewardDuration);
    }

    lastUpdateTime = block.timestamp;
    periodFinish = block.timestamp.add(rewardDuration);

    emit RewardAdded(rewardAmount);
  }

  /// @notice Update the rewards duration
  /// @dev Can only be called by the owner
  /// @param _rewardDuration the rewards duration
  function updateRewardDuration(uint256 _rewardDuration) external onlyOwner {
    rewardDuration = _rewardDuration;

    emit RewardDurationUpdated(_rewardDuration);
  }

  /// @notice Update the boosted time period
  /// @dev Can only be called by the owner
  /// @param _boostedTimePeriod the boosted time period
  function updateBoostedTimePeriod(uint256 _boostedTimePeriod)
    external
    onlyOwner
  {
    boostedTimePeriod = _boostedTimePeriod;

    emit BoostedTimePeriodUpdated(_boostedTimePeriod);
  }

  /// @notice Update the boost
  /// @dev Can only be called by the owner
  /// @param _boost the boost
  function updateBoost(uint256 _boost) external onlyOwner {
    boost = _boost;

    emit BoostUpdated(_boost);
  }

  /// @notice Adds to the contract whitelist
  /// @dev Can only be called by the owner
  /// @param _contract the contract to be added to the whitelist
  function addToContractWhitelist(address _contract) external onlyOwner {
    _addToContractWhitelist(_contract);
  }

  /// @notice Removes from the contract whitelist
  /// @dev Can only be called by the owner
  /// @param _contract the contract to be removed from the whitelist
  function removeFromContractWhitelist(address _contract) external onlyOwner {
    _removeFromContractWhitelist(_contract);
  }

  /* ========== MODIFIERS ========== */

  // Modifier *Update Reward modifier*
  modifier updateReward(address account) {
    uint256 perTokenRate = rewardPerToken();
    lastUpdateTime = lastTimeRewardApplicable();
    if (account != address(0)) {
      rewardEarned[account] = earned(account);
      userRewardPerTokenPaid[account] = perTokenRate;
    }
    _;
  }

  /* ========== EVENTS ========== */

  event EmergencyWithdraw(address sender);
  event RewardDurationUpdated(uint256 rewardDuration);
  event BoostedTimePeriodUpdated(uint256 boostedTimePeriod);
  event BoostUpdated(uint256 boost);
  event RewardAdded(uint256 rewardAmount);
  event Staked(address indexed user, uint256 amount);
  event Unstaked(address indexed user, uint256 amount);
  event RewardPaid(address indexed user, uint256 reward);
}

