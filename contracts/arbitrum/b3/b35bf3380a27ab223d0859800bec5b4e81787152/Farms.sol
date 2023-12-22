// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./ReentrancyGuard.sol";
import "./Pausable.sol";
import "./Ownable.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./IYieldBooster.sol";
import "./ITokenManager.sol";


contract Farms is ReentrancyGuard, Ownable, Pausable {
  using SafeERC20 for IERC20;

  /* ========== STATE VARIABLES ========== */

  // Counter for total number of farms created
  uint256 public totalFarms;
  // Contract address for the Steady token
  address public immutable steady;
  // Contract address for the Token Manager
  address public tokenManager;
  // Address for Yield Booster plugin for multiplier
  address public yieldBooster;

  /* ========== CONSTANTS ========== */

  uint256 public constant SAFE_MULTIPLIER = 1e18;
  uint256 public constant MAX_REWARDS_SPLIT = 100 * 1e18; // 100%
  uint256 public constant MIN_MULTIPLIER = 1 * 1e18; // 1x

  /* ========== STRUCTS ========== */

  struct Farm {
    // Unique id number of farm
    uint256 id;
    // Boolean for whether farm is active or not
    bool active;
    // Contract address for the staked token
    address stakedToken;
    // Amount of rewards to be distributed per second
    uint256 rewardsDistributionRate;
    // Internal calculation of rewards accrued per staked token
    uint256 rewardsPerStakedToken;
    // Block timestamp which this farm was last updated at
    uint256 lastUpdatedAt;
    // Total amount of tokens staked in this farm
    uint256 totalStaked;
    // Total amount of boosted points in this farm
    uint256 totalPoints;
    // Total amount of reward tokens deposited in this farm
    uint256 totalRewards;
    // % split of total rewards to be given in steady; 100% = 1e18
    uint256 esSteadySplit;
    // Maximum multiplier in 1e18
    uint256 maxMultiplier;
    // Block timestamp when farm is scheduled to end
    uint256 endTime;
  }

  struct Position {
    // Amount of tokens staked by user in a farm position
    uint256 stakedAmount;
    // Calculation for tracking rewards owed to user based on stake changes
    uint256 rewardsDebt;
    // Total rewards redeemed by user
    uint256 rewardsRedeemed;
    // Amount of boosted points by user in a farm position
    uint256 pointsAmount;
  }

  /* ========== MAPPINGS ========== */

  // Mapping of farm id to Farm struct
  mapping(uint256 => Farm) public farms;
  // Mapping of farm id to user position address to Position struct
  mapping(uint256 => mapping(address => Position)) public positions;

  /* ========== EVENTS ========== */

  event Stake(uint256 indexed farmId, address indexed user, address token, uint256 amount);
  event Unstake(uint256 indexed farmId, address indexed user, address token, uint256 amount);
  event Claim(uint256 indexed farmId, address indexed user, address token, uint256 amount);
  event Boost(uint256 indexed farmId, address indexed user, uint256 amount);
  event Unboost(uint256 indexed farmId, address indexed user, uint256 amount);
  event UpdateActive(uint256 indexed farmId, bool active);
  event UpdateRewardsDistributionRate(uint256 indexed farmId, uint256 rate);
  event UpdateEsSteadySplit(uint256 indexed farmId, uint256 esSteadySplit);
  event UpdateMaxMultiplier(uint256 indexed farmId, uint256 maxMultiplier);
  event UpdateEndTime(uint256 indexed farmId, uint256 endTime);
  event UpdateYieldBooster(address indexed caller, uint256 timestamp);
  event UpdateTokenManager(address indexed tokenManager);
  event DepositRewardTokens(uint256 indexed farmId, uint256 amount);
  event WithdrawRewardTokens(uint256 indexed farmId, uint256 amount);

  /* ========== MODIFIERS ========== */

  /**
    * Only allow approved addresses for keepers
  */
  modifier onlyYieldBooster() {
    require(msg.sender == yieldBooster, "Only YieldBooster caller allowed");
    _;
  }

  /* ========== CONSTRUCTOR ========== */

  constructor(address _steady, address _tokenManager) {
    require(_steady != address(0), "invalid 0 address");
    require(_tokenManager != address(0), "invalid 0 address");

    steady = _steady;
    tokenManager = _tokenManager;

    IERC20(steady).approve(address(tokenManager), type(uint256).max);
  }

  /* ========== VIEW FUNCTIONS ========== */

  /**
  * Calculate the current reward accrued per token staked
  * @param _id  Unique id of farm
  * @return currentRewardPerStakedToken Current reward per staked token
  */
  function currentRewardPerStakedToken(uint256 _id) private view returns (uint256) {
    Farm storage farm = farms[_id];

    if (farm.totalStaked == 0) {
      return farm.rewardsDistributionRate;
    }

    uint256 time = block.timestamp > farm.endTime ? farm.endTime : block.timestamp;

    return (time - farm.lastUpdatedAt)
            * farm.rewardsDistributionRate
            * SAFE_MULTIPLIER
            / farm.totalStaked
            + farm.rewardsPerStakedToken;
  }

  /**
  * Returns the reward tokens currently accrued but not yet redeemed to a user
  * @param _id  Unique id of farm
  * @param _user  Address of a user
  * @return rewardsEarned Total rewards accrued to user
  */
  function rewardsEarned(uint256 _id, address _user) public view returns (uint256) {
    Position memory position = positions[_id][_user];

    if (position.stakedAmount <= 0 || currentRewardPerStakedToken(_id) <= 0) return 0;

    return ((position.stakedAmount * currentRewardPerStakedToken(_id)
            * getRewardMultiplier(_id, _user)
            / SAFE_MULTIPLIER)
            - position.rewardsDebt)
            / SAFE_MULTIPLIER;
  }

  /**
  * Returns the reward multiplier of a user's farm position
  * @param _id  Unique id of farm
  * @param _user  Address of a user
  * @return multiplier  Multiplier in 1e18
  */
  function getRewardMultiplier(uint256 _id, address _user) public view returns (uint256) {
    if (yieldBooster != address(0)) {
      Farm memory farm = farms[_id];
      Position memory position = positions[_id][_user];

      return IYieldBooster(yieldBooster).getMultiplier(
        position.stakedAmount,
        farm.totalStaked,
        position.pointsAmount,
        farm.totalPoints,
        farm.maxMultiplier
      );
    } else {
      return MIN_MULTIPLIER;
    }
  }

  /* ========== INTERNAL FUNCTIONS ========== */

  /**
  Update farm's reward per staked token value
  * @param _id  Unique id of farm
  */
  function _updateFarm(uint256 _id) internal {
    Farm memory farm = farms[_id];

    if (farm.totalStaked > 0 && farm.lastUpdatedAt < farm.endTime) {
      uint256 time = block.timestamp > farm.endTime ? farm.endTime : block.timestamp;

      farm.rewardsPerStakedToken = (time - farm.lastUpdatedAt)
        * farm.rewardsDistributionRate
        * SAFE_MULTIPLIER
        / farm.totalStaked
        + farm.rewardsPerStakedToken;
    }

    if (farm.lastUpdatedAt != farm.endTime) {
      farm.lastUpdatedAt = block.timestamp < farm.endTime ? block.timestamp
                                                          : farm.endTime;
    }

    farms[_id] = farm;
  }

  /**
  * Private function used for updating the user rewardsDebt variable
  * Called when user's stake changes
  * @param _id  Unique id of farm
  * @param _user  Address of a user
  * @param _amount  Amount of new tokens staked or amount of tokens left in farm
  */
  function _updateUserRewardsDebt(uint256 _id, address _user, uint256 _amount) private {
    Position storage position = positions[_id][_user];

    position.rewardsDebt = position.rewardsDebt
                          + (_amount * farms[_id].rewardsPerStakedToken
                          * getRewardMultiplier(_id, _user)
                          / SAFE_MULTIPLIER);
  }

  /* ========== MUTATIVE FUNCTIONS ========== */

  /**
  * External function called when a user wants to stake tokens
  * Called when user is depositing tokens to stake
  * @param _id  Unique id of farm
  * @param _amount  Amount of tokens to stake
  */
  function stake(uint256 _id, uint256 _amount) external nonReentrant whenNotPaused {
    require(_id < totalFarms, "Cannot stake from an unexisting farm");
    require(farms[_id].active, "Farm is not active");
    require(_amount > 0, "Cannot stake 0");

    claim(_id);
    _updateFarm(_id);
    _updateUserRewardsDebt(_id, msg.sender, _amount);

    Position storage position = positions[_id][msg.sender];
    Farm storage farm = farms[_id];

    position.stakedAmount = position.stakedAmount + _amount;

    farm.totalStaked = farm.totalStaked + _amount;

    IERC20(farm.stakedToken).safeTransferFrom(msg.sender, address(this), _amount);

    emit Stake(_id, msg.sender, farm.stakedToken, _amount);
  }

  /**
  * External function called when a user wants to unstake tokens
  * Called when user is withdrawing staked tokens
  * @param _id  Unique id of farm
  * @param _amount  Amount of tokens to withdraw/unstake
  */
  function unstake(uint256 _id, uint256 _amount) public nonReentrant whenNotPaused {
    require(_id < totalFarms, "Cannot unstake from an unexisting farm");
    require(_amount > 0, "Cannot unstake 0");

    Position storage position = positions[_id][msg.sender];

    require(position.stakedAmount >= _amount, "Cannot unstake more than staked");

    claim(_id);
    _updateFarm(_id);

    position.rewardsDebt = 0;
    position.stakedAmount = position.stakedAmount - _amount;

    _updateUserRewardsDebt(_id, msg.sender, position.stakedAmount);

    Farm storage farm = farms[_id];
    farm.totalStaked = farm.totalStaked - _amount;

    IERC20(farm.stakedToken).safeTransfer(msg.sender, _amount);

    emit Unstake(_id, msg.sender, farm.stakedToken, _amount);
  }

  /**
  * External function called when a user wants to redeem reward tokens earned
  * @param _id  Unique id of farm
  */
  function claim(uint256 _id) public whenNotPaused {
    require(_id < totalFarms, "Cannot claim from an unexisting farm");

    uint256 rewards = rewardsEarned(_id, msg.sender);

    if (rewards > 0) {
      Farm storage farm = farms[_id];

      require(
        farm.totalRewards >= rewards,
        "Rewards deposited in farm less than rewards claimable"
      );

      Position memory position = positions[_id][msg.sender];

      position.rewardsRedeemed = position.rewardsRedeemed + rewards;
      position.rewardsDebt = position.stakedAmount * currentRewardPerStakedToken(_id)
                            * getRewardMultiplier(_id, msg.sender)
                            / SAFE_MULTIPLIER;
      positions[_id][msg.sender] = position;

      farm.totalRewards -= rewards;

      if (farm.esSteadySplit > 0) {
        uint256 esSteadyAmount = rewards * farm.esSteadySplit / SAFE_MULTIPLIER;
        uint256 steadyAmount = rewards - esSteadyAmount;

        IERC20(steady).safeTransfer(msg.sender, steadyAmount);
        ITokenManager(tokenManager).convertTo(esSteadyAmount, msg.sender);
        } else {
        IERC20(steady).safeTransfer(msg.sender, rewards);
      }

      emit Claim(_id, msg.sender, steady, rewards);
    }
  }

  /**
  * External function called when a user wants to redeem all accrued reward tokens
  * @param _ids  Array of farm ids to claim from
  */
  function claimAll(uint256[] calldata _ids) public nonReentrant whenNotPaused {
    for (uint256 i = 0; i < _ids.length;) {
      claim(_ids[i]);
      unchecked { i++; }
    }
  }

  /**
  * Boost a farm position with esSteady to increase multiplier for rewards
  * Callable only by the YieldBooster contract
  * @param _id  Unique id of farm
  * @param _user  Address of user farm position
  * @param _amount  Amount of esSteady points to boost this position
  */
  function boost(
    uint256 _id,
    address _user,
    uint256 _amount
  ) external nonReentrant whenNotPaused onlyYieldBooster {
    require(_id < totalFarms, "Cannot boost an unexisting farm");
    require(farms[_id].active, "Farm is not active");
    require(_user != address(0), "Invalid zero address");
    require(_amount > 0, "Cannot boost 0");

    claim(_id);
    _updateFarm(_id);
    _updateUserRewardsDebt(_id, _user, _amount);

    Position storage position = positions[_id][_user];
    Farm storage farm = farms[_id];

    position.pointsAmount = position.pointsAmount + _amount;
    farm.totalPoints = farm.totalPoints + _amount;

    emit Boost(_id, _user, _amount);
  }


  /**
  * Unboost a farm position of esSteady, reducing multiplier for rewards
  * Callable only by the YieldBooster contract
  * @param _id  Unique id of farm
  * @param _user  Address of user farm position
  * @param _amount  Amount of esSteady points to unboost this position
  */
  function unboost(
    uint256 _id,
    address _user,
    uint256 _amount
  ) external nonReentrant whenNotPaused onlyYieldBooster {
    require(_id < totalFarms, "Cannot unboost an unexisting farm");
    require(farms[_id].active, "Farm is not active");
    require(_user != address(0), "Invalid zero address");
    require(_amount > 0, "Cannot boost 0");

    claim(_id);
    _updateFarm(_id);
    _updateUserRewardsDebt(_id, _user, _amount);

    Position storage position = positions[_id][_user];
    Farm storage farm = farms[_id];

    position.pointsAmount = position.pointsAmount - _amount;
    farm.totalPoints = farm.totalPoints - _amount;

    emit Unboost(_id, _user, _amount);
  }

  /* ========== RESTRICTED FUNCTIONS ========== */

  /**
  * Create a new Farm
  * @param _active  Boolean for whether farm is active or not
  * @param _stakedToken Contract address for the staked tokens
  * @param _rewardsDistributionRate  Amount of rewards to be distributed per second
  * @param _esSteadySplit  % split of total rewards to be given in esSteady
  * @param _maxMultiplier  Max multiplier in 1e18
  * @param _endTime  Timestamp for when farm will end
  */
  function createFarm(
    bool _active,
    address _stakedToken,
    uint256 _rewardsDistributionRate,
    uint256 _esSteadySplit,
    uint256 _maxMultiplier,
    uint256 _endTime
  ) external onlyOwner {
    require(_stakedToken != address(0), "Staked token cannot be zero address");
    require(_endTime > block.timestamp, "End time must be greater than current time");
    require(_maxMultiplier >= SAFE_MULTIPLIER, "Max multiplier must be greater than 1x");

    Farm memory farm = Farm({
      id: totalFarms,
      active: _active,
      stakedToken: _stakedToken,
      rewardsDistributionRate: _rewardsDistributionRate,
      esSteadySplit: _esSteadySplit,
      rewardsPerStakedToken: 0,
      lastUpdatedAt: block.timestamp,
      totalStaked: 0,
      totalPoints: 0,
      totalRewards: 0,
      maxMultiplier: _maxMultiplier,
      endTime: _endTime
    });

    farms[totalFarms] = farm;
    totalFarms += 1;
  }

  /**
  * Deposit more reward tokens to a farm
  * @param _id  Unique id of farm
  * @param _amount  Amount of reward tokens to deposit; in reward token's decimals
  */
  function depositRewardsTokens(uint256 _id, uint256 _amount) external nonReentrant onlyOwner {
    require(_amount > 0, "Cannot deposit 0 amount");
    require(_id < totalFarms, "Cannot deposit to unexisting farm");

    Farm storage farm = farms[_id];

    IERC20(steady).safeTransferFrom(msg.sender, address(this), _amount);
    farm.totalRewards += _amount;

    emit DepositRewardTokens(_id, _amount);
  }

  /**
  * Deposit more reward tokens to a farm
  * @param _id  Unique id of farm
  * @param _amount  Amount of reward tokens to deposit; in reward token's decimals
  */
  function withdrawRewardsTokens(uint256 _id, uint256 _amount) external nonReentrant onlyOwner {
    Farm storage farm = farms[_id];
    require(_amount > 0, "Cannot withdraw 0 amount");
    require(_id < totalFarms, "Cannot withdraw from unexisting farm");
    require(
      farm.totalRewards > 0, "Cannot withdraw when farm has no reward tokens deposited"
    );
    require(
      _amount <= farm.totalRewards,
      "Cannot withdraw more reward tokens than deposited in farm"
    );

    farm.totalRewards -= _amount;
    IERC20(steady).safeTransfer(msg.sender, _amount);

    emit WithdrawRewardTokens(_id, _amount);
  }

  /**
  * Update a farm's active status
  * @param _id  Unique id of farm
  * @param _active  Boolean to set farm to be active or not
  */
  function updateActive(uint256 _id, bool _active) external onlyOwner {
    require(_id < totalFarms, "Cannot update an unexisting farm");

    farms[_id].active = _active;

    emit UpdateActive(_id, _active);
  }

  /**
  * Update the reward token distribution rate
  * @param _id  Unique id of farm
  * @param _rate  Rate of reward token distribution per second
  */
  function updateRewardsDistributionRate(uint256 _id, uint256 _rate) external onlyOwner {
    require(_id < totalFarms, "Cannot update an unexisting farm");
    require(_rate >= 0, "Rate must be >= 0");

    farms[_id].rewardsDistributionRate = _rate;
    _updateFarm(_id);

    emit UpdateRewardsDistributionRate(_id, _rate);
  }

  /**
  * Update the rewards split % of total rewards to esSteady
  * @param _id  Unique id of farm
  * @param _esSteadySplit  Rewards split % of total rewards to esSteady
  */
  function updateEsSteadySplit(uint256 _id, uint256 _esSteadySplit) external onlyOwner {
    require(_id < totalFarms, "Cannot update an unexisting farm");
    require(_esSteadySplit <= MAX_REWARDS_SPLIT, "Reward split must be less maximum");

    farms[_id].esSteadySplit = _esSteadySplit;
    _updateFarm(_id);

    emit UpdateEsSteadySplit(_id, _esSteadySplit);
  }

  /**
  * Update the max multiplier of a farm
  * @param _id  Unique id of farm
  * @param _maxMultiplier  Rewards split % of total rewards to esSteady
  */
  function updateMaxMultiplier(uint256 _id, uint256 _maxMultiplier) external onlyOwner {
    require(_id < totalFarms, "Cannot update an unexisting farm");
    require(_maxMultiplier >= SAFE_MULTIPLIER, "Max multiplier must be greater than 1x");

    farms[_id].maxMultiplier = _maxMultiplier;
    _updateFarm(_id);

    emit UpdateMaxMultiplier(_id, _maxMultiplier);
  }

  /**
  * Update the end time of a farm
  * @param _id  Unique id of farm
  * @param _endTime  Timestamp of end time for farm
  */
  function updateEndTime(uint256 _id, uint256 _endTime) external onlyOwner {
    require(_id < totalFarms, "Cannot update an unexisting farm");
    require(_endTime > block.timestamp, "End time must be greater than current time");

    farms[_id].endTime = _endTime;
    _updateFarm(_id);

    emit UpdateEndTime(_id, _endTime);
  }

  /**
  * Update yield booster plugin contract address
  * @param _yieldBooster  Address of yield booster contract
  */
  function updateYieldBooster(address _yieldBooster) external onlyOwner {
    yieldBooster = _yieldBooster;

    emit UpdateYieldBooster(msg.sender, block.timestamp);
  }

  /**
  * Update STEADY token manager contract address
  * @param _tokenManager  Address of token manager contract
  */
  function updateTokenManager(address _tokenManager) external onlyOwner {
    require(_tokenManager != address(0), "invalid zero address");

    tokenManager = _tokenManager;

    emit UpdateTokenManager(_tokenManager);
  }

  /**
  * Pause farms contract
  */
  function pause() external onlyOwner {
    _pause();
  }

  /**
  * Pause farms contract
  */
  function unpause() external onlyOwner {
    _unpause();
  }
}

