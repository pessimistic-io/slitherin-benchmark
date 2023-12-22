/*
@@@@@@@@@@@@@@@@@@@@@@@@@@@@&#G5J?7!~~~::::::::::::::::~^^^:::::^:G@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@#GY7~:.                                    5@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@#P?^.                                          5@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@#Y!.                    ~????????????????????????7B@@@@@@@@@@@@@
@@@@@@@@@@@@@&P!.                       5@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@&Y:                          5@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@&Y:                      .::^~^7YYYYYYYYYYYYYYYYYYYYYYYYY#@@@@@@@@@@@@@
@@@@@@@@P:                  .^7YPB#&@@@&.                         5@@@@@@@@@@@@@
@@@@@@&7                 :?P#@@@@@@@@@@&.                         5@@@@@@@@@@@@@
@@@@@B:               .7G&@@@@@@@@@&#BBP.                         5@@@@@@@@@@@@@
@@@@G.              .J#@@@@@@@&GJ!^:.                             5@@@@@@@@@@@@@
@@@G.              7#@@@@@@#5~.                                   5@@@@@@@@@@@@@
@@#.             :P@@@@@@#?.                                      5@@@@@@@@@@@@@
@@~             :#@@@@@@J.       .~JPGBBBBBBBBBBBBBBBBBBBBBBBBBBBB&@@@@@@@@@@@@@
@5             .#@@@@@&~       !P&@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@~             P@@@@@&^      ^G@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
B             ~@@@@@@7      ^&@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
5             5@@@@@#      .#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
Y   ..     .. P#####5      7@@@@@@@@@@@@@@@@@@@@@@@@&##########################&
@############B:    .       !@@@@@@@@@@@@@@@@@@@@@@@@5            ..            7
@@@@@@@@@@@@@@:            .#@@@@@@@@@@@@@@@@@@@@@@@~                          7
@@@@@@@@@@@@@@J             ~&@@@@@@@@@@@@@@@@@@@@@?       ......              5
@@@@@@@@@@@@@@#.             ^G@@@@@@@@@@@@@@@@@@#!      .G#####G.            .#
@@@@@@@@@@@@@@@P               !P&@@@@@@@@@@@@@G7.      :G@@@@@@~             ?@
@@@@@@@@@@@@@@@@5                :!JPG####BPY7:        7#@@@@@&!             :#@
@@@@@@@@@@@@@@@@@P:                   ....           !B@@@@@@#~              P@@
@@@@@@@@@@@@@@@@@@#!                             .^J#@@@@@@@Y.              J@@@
@@@@@@@@@@@@@@@@@@@@G~                      .^!JP#@@@@@@@&5^               Y@@@@
@@@@@@@@@@@@@@@@@@@@@@G7.               ?BB#&@@@@@@@@@@#J:                5@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@&P7:            5@@@@@@@@@@&GJ~.                ^B@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@B5?~:.      5@@@@&#G5?~.                  .Y@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@#BGP5YJ~~~^^..                      ?#@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@&.                         .?B@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@&.                       ^Y&@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@&.                    ^JB@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@&.                :!5#@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@&.         ..^!JP#@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@&~::^~!7?5PB&@@@@@@@@@@@@@@@@@@@@@@@@@@@@*/

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./draft-ERC20Permit.sol";
import "./ERC20Pausable.sol";
import "./ERC20Capped.sol";
import "./ReentrancyGuard.sol";
import "./AccessControl.sol";
import "./Ownable2Step.sol";
import "./Address.sol";
import "./Chef.sol";
import "./ICSS.sol";
import "./ITokenVesting.sol";

contract MasterChef is Ownable2Step, Chef, ReentrancyGuard {
  uint256 public constant MAX_PERCENT = 100_00;

  struct PoolInfo {
    IERC20 token; // Address of token contract. This must not be changed once initialized.
    uint256 total; // Total token in pool.
    uint256 startTime; // Timestamp to start distribute reward. This must not be changed once initialized.
    uint256 lockInterval; // Lock interval in seconds.
    uint256 depositFeePercent; // Deposit fee percentage.
    uint256 harvestInterval; // Harvest interval in seconds.
    address[] rewardTokens; // Address list of token to distribute reward. This must not be changed once initialized.
    mapping(address => uint256) allocPoints; // How many allocation points assigned to this pool.
    mapping(address => uint256) accTokenPerShares; // Accumulated token per share, times `ACC_TOKEN_PRECISION`.
    uint256 lastRewardTime; // Last block timestamp that reward distribution occurs.
  }

  struct UserInfo {
    uint256 amount; // How many LP tokens the user has provided.
    mapping(address => uint256) rewardDebt; // Reward debt.
    mapping(address => uint256) lockedUp; // Reward locked up.
    uint256 nextHarvestUntil; // When can the user harvest again.
    uint256 nextUnlockUntil; //  When can the user can withdraw again.
  }

  event AddPool(
    uint256 indexed pId,
    IERC20 indexed token,
    uint256 startTime,
    uint256 lockInterval,
    uint256 depositFeePercent,
    uint256 harvestInterval,
    address[] rewardTokens,
    uint256[] allocPoints
  );
  event SetPool(
    uint256 indexed pId, uint256 lockInterval, uint256 depositFeePercent, uint256 harvestInterval, uint256[] allocPoints
  );
  event Deposit(address indexed user, uint256 indexed pId, uint256 amount);
  event Withdraw(address indexed user, uint256 indexed pId, uint256 amount);
  event ClaimReward(uint256 pId, address userAddr, address[] rewardTokens, uint256[] values);
  event LockReward(uint256 pId, address userAddr, address[] rewardTokens, uint256[] values);
  event SetRewardPerSec(address[] tokens, uint256[] rewardPerSecs);

  /// @dev The precision factor.
  uint256 private constant ACC_TOKEN_PRECISION = 1e12;

  /// @dev Maximum deposit fee rate: 10%
  uint16 public constant MAXIMUM_DEPOSIT_FEE_RATE = 10_00;
  /// @dev Max harvest interval: 14 days
  uint256 public constant MAXIMUM_HARVEST_INTERVAL = 14 days;
  /// @dev Max harvest interval: 30 days
  uint256 public constant MAXIMUM_LOCK_INTERVAL = 30 days;

  IERC20 public immutable cssToken;
  /// @dev Wrapped ether address.
  address public immutable WETH;
  /// @dev Token Vesting.
  ITokenVesting public immutable tokenVesting;

  /// @dev Info of each pool.
  PoolInfo[] public poolInfo;
  /// @dev Info of each user that stakes tokens.
  mapping(uint256 => mapping(address => UserInfo)) public userInfo;

  /// @dev Reward token distribution per seconds.
  mapping(address => uint256) private rewardPerSec;
  /// @dev Total allocation points assigned of  each pool.
  mapping(address => uint256) private totalAllocPoints;

  modifier hasPool(uint256 pId) {
    require(pId < poolInfo.length, "MasterChef: pool info");
    _;
  }

  constructor(address admin, address weth, ITokenVesting _tokenVesting, IERC20 _cssToken) {
    require(_tokenVesting.IS_CONSENSUS_VESTING(), "MasterChef: incorrect vesting");
    _transferOwnership(admin);
    cssToken = _cssToken;
    tokenVesting = _tokenVesting;
    WETH = weth;
  }

  /**
   * @dev Returns the number of pool.
   */
  function totalPools() external view returns (uint256) {
    return poolInfo.length;
  }

  /**
   * @dev Returns the locked tokens of pools.
   *
   * @return tokens array of token addresses to query.
   * @return totals the amount of token that being locked.
   */
  function getLockedTokens(uint256[] calldata pIds)
    external
    view
    returns (IERC20[] memory tokens, uint256[] memory totals)
  {
    uint256 length = pIds.length;
    tokens = new IERC20[](length);
    totals = new uint256[](length);
    for (uint256 i; i < length; i++) {
      uint256 pId = pIds[i];
      require(pId < poolInfo.length, "MasterChef: invalid pId");
      tokens[i] = poolInfo[pId].token;
      totals[i] = poolInfo[pId].total;
    }
  }

  /**
   * @dev Returns the locked tokens of an user in some pools.
   *
   * @return tokens array of token addresses to query.
   * @return amounts the amount of token that being locked by the user.
   */
  function getLockedTokensOfUser(uint256[] calldata pIds, address user)
    external
    view
    returns (IERC20[] memory tokens, uint256[] memory amounts)
  {
    uint256 length = pIds.length;
    tokens = new IERC20[](length);
    amounts = new uint256[](length);
    for (uint256 i; i < length; i++) {
      uint256 pId = pIds[i];
      require(pId < poolInfo.length, "MasterChef: invalid pId");
      tokens[i] = poolInfo[pId].token;
      amounts[i] = userInfo[pId][user].amount;
    }
  }

  /**
   *
   * @dev Returns pool reward per sec of a pool.
   *
   * @param pId id of the pool.
   *
   * @return tokens array of queried token addresses.
   * @return rewardPerSecs the reward rate per second.
   */
  function getPoolRewardPerSecs(uint256 pId)
    external
    view
    hasPool(pId)
    returns (address[] memory tokens, uint256[] memory rewardPerSecs)
  {
    PoolInfo storage pool = poolInfo[pId];
    tokens = pool.rewardTokens;
    rewardPerSecs = new uint256[](tokens.length);
    for (uint256 i = 0; i < rewardPerSecs.length; i++) {
      address token = tokens[i];
      rewardPerSecs[i] = rewardPerSec[token] * pool.allocPoints[token] / totalAllocPoints[token];
    }
  }

  /**
   * @dev Returns the reward per seconds and its total allocation.
   *
   * @param tokens array of token addresses to query
   */
  function getRewardAllocs(address[] calldata tokens)
    external
    view
    returns (uint256[] memory rewardPerSecs, uint256[] memory totalAllocationPoints)
  {
    rewardPerSecs = new uint256[](tokens.length);
    totalAllocationPoints = new uint256[](tokens.length);
    for (uint256 i; i < rewardPerSecs.length; i++) {
      address token = tokens[i];
      rewardPerSecs[i] = rewardPerSec[token];
      totalAllocationPoints[i] = totalAllocPoints[token];
    }
  }

  /**
   * @dev Sets reward per second to each token.
   *
   * Emits a {SetRewardPerSec} event.
   *
   * Requirements:
   *
   * - the caller must be admin.
   *
   * @param tokens array of token addresses for setting
   * @param rewardPerSecs the reward emission for each one
   */
  function setRewardPerSec(address[] calldata tokens, uint256[] calldata rewardPerSecs) external onlyOwner {
    require(tokens.length > 0 && tokens.length == rewardPerSecs.length, "MasterChef: invalid array");
    for (uint256 i = 0; i < tokens.length; i++) {
      rewardPerSec[tokens[i]] = rewardPerSecs[i];
    }
    emit SetRewardPerSec(tokens, rewardPerSecs);
  }

  /**
   * @dev See {MasterChef-_createPool}.
   */
  function createPoolNow(
    IERC20 token,
    uint256 lockInterval,
    uint256 depositFeePercent,
    uint256 harvestInterval,
    address[] calldata rewardTokens,
    uint256[] calldata allocPoints
  ) external onlyOwner returns (uint256 pId) {
    pId =
      _createPool(token, block.timestamp, lockInterval, depositFeePercent, harvestInterval, rewardTokens, allocPoints);
  }

  /**
   * @dev Sets a token pool.
   *
   * Emits a {SetPool} event.
   *
   * Requirements:
   *
   * - the caller must be admin.
   * - the array lengths are equal.
   * - the pool exists.
   *
   * @param pId id of the pool.
   * @param allocPoints how many allocation points assigned to the reward tokens.
   */
  function setPool(
    uint256 pId,
    uint256 lockInterval,
    uint256 depositFeePercent,
    uint256 harvestInterval,
    uint256[] calldata allocPoints
  ) external onlyOwner hasPool(pId) {
    PoolInfo storage pool = poolInfo[pId];
    require(pool.rewardTokens.length == allocPoints.length, "MasterChef: array length");
    require(lockInterval <= MAXIMUM_LOCK_INTERVAL, "MasterChef: invalid lockInterval");
    require(depositFeePercent <= MAXIMUM_DEPOSIT_FEE_RATE, "MasterChef: invalid depositFeePercent");
    require(harvestInterval <= MAXIMUM_HARVEST_INTERVAL, "MasterChef: invalid harvestInterval");

    pool.lockInterval = lockInterval;
    pool.depositFeePercent = depositFeePercent;
    pool.harvestInterval = harvestInterval;
    for (uint256 i; i < pool.rewardTokens.length; i++) {
      address token = pool.rewardTokens[i];
      totalAllocPoints[token] -= pool.allocPoints[token];
      pool.allocPoints[token] = allocPoints[i];
      totalAllocPoints[token] += allocPoints[i];
    }
    emit SetPool(pId, lockInterval, depositFeePercent, harvestInterval, allocPoints);
  }

  /**
   * @dev Updates reward vairables for all pools. Be careful of gas spending.
   */
  function massUpdatePools() public {
    uint256 length = poolInfo.length;
    for (uint256 pId; pId < length; ++pId) {
      updatePool(pId);
    }
  }

  /**
   * @dev Updates reward variables of the given pool to be up-to-date.
   *
   * Requirements:
   *
   * - the pool exists.
   *
   * @param pId id of the pool.
   */
  function updatePool(uint256 pId) public hasPool(pId) {
    PoolInfo storage pool = poolInfo[pId];
    if (block.timestamp <= pool.lastRewardTime) {
      return;
    }

    tokenVesting.emitToken();

    uint256 totalAmount = pool.total;
    if (totalAmount == 0) {
      pool.lastRewardTime = block.timestamp;
      return;
    }

    uint256 lastRewardTime = pool.lastRewardTime;
    address[] memory rewardTokens = pool.rewardTokens;
    for (uint256 i; i < rewardTokens.length; i++) {
      address token = rewardTokens[i];
      uint256 allocPoint = pool.allocPoints[token];
      uint256 tokenPerSec = rewardPerSec[token];
      uint256 duration = _getPassedDuration(pool.startTime, lastRewardTime);
      uint256 totalAllocPoint = totalAllocPoints[token];

      uint256 reward = duration * tokenPerSec * allocPoint / totalAllocPoint;
      pool.accTokenPerShares[token] += reward * ACC_TOKEN_PRECISION / totalAmount;
    }
    pool.lastRewardTime = block.timestamp;
  }

  /**
   * @dev View function to see pending reward in many pools on frontend.
   *
   * Requirements:
   *
   * - the pool exists.
   *
   * @param pIds idl list of the pool.
   * @param userAddr address of the user.
   *
   * @return rewardTokens token address list to distribute rewards.
   * @return rewards the corresponding reward to token.
   */
  function getRewards(uint256[] calldata pIds, address userAddr)
    external
    view
    returns (address[][] memory rewardTokens, uint256[][] memory rewards)
  {
    uint256 length = pIds.length;
    rewardTokens = new address[][](length);
    rewards = new uint256[][](length);
    for (uint256 i; i < length; i++) {
      (rewardTokens[i], rewards[i]) = getReward(pIds[i], userAddr);
    }
  }

  /**
   * @dev View function to see pending reward on frontend.
   *
   * Requirements:
   *
   * - the pool exists.
   *
   * @param pId id of the pool.
   * @param userAddr address of the user.
   *
   * @return rewardTokens token address list to distribute rewards.
   * @return rewards the corresponding reward to token.
   */
  function getReward(uint256 pId, address userAddr)
    public
    view
    hasPool(pId)
    returns (address[] memory rewardTokens, uint256[] memory rewards)
  {
    PoolInfo storage pool = poolInfo[pId];
    UserInfo storage user = userInfo[pId][userAddr];

    rewardTokens = pool.rewardTokens;
    rewards = new uint256[](rewardTokens.length);
    uint256 totalAmount = pool.total;
    uint256 lastRewardTime = pool.lastRewardTime;

    for (uint256 i; i < rewards.length; i++) {
      address token = rewardTokens[i];
      uint256 accTokenPerShare = pool.accTokenPerShares[token];
      if (block.timestamp > lastRewardTime && totalAmount > 0) {
        uint256 tokenPerSec = rewardPerSec[token];
        uint256 allocPoint = pool.allocPoints[token];
        uint256 totalAllocPoint = totalAllocPoints[token];

        uint256 duration = _getPassedDuration(pool.startTime, lastRewardTime);
        uint256 reward = duration * tokenPerSec * allocPoint / totalAllocPoint;
        accTokenPerShare += reward * ACC_TOKEN_PRECISION / totalAmount;
      }
      rewards[i] = user.amount * accTokenPerShare / ACC_TOKEN_PRECISION - user.rewardDebt[token] + user.lockedUp[token];
    }
  }

  /**
   * @dev Deposits token to MasterChef.
   *
   * Emits a {Deposit} event.
   *
   * Requirements:
   *
   * - the pool exists.
   * - the user must approve pool token.
   *
   * @param pId id of the pool.
   * @param amount amount of token to transfer.
   */
  function deposit(uint256 pId, uint256 amount) external hasPool(pId) nonReentrant {
    address userAddr = msg.sender;
    PoolInfo storage pool = poolInfo[pId];
    UserInfo storage user = userInfo[pId][userAddr];
    updatePool(pId);

    address[] memory rewardTokens = pool.rewardTokens;
    if (user.amount > 0) {
      (, rewardTokens,) = _payOrLockupPending(pId, userAddr);
    } else if (user.nextHarvestUntil == 0) {
      user.nextHarvestUntil = block.timestamp + pool.harvestInterval;
    }

    {
      uint256 depositFee = amount * pool.depositFeePercent / MAX_PERCENT;
      amount -= depositFee;
      require(pool.token.transferFrom(userAddr, address(this), amount), "MasterChef: cannot deposit token");
      if (depositFee > 0) {
        require(pool.token.transferFrom(userAddr, tokenVesting.teamWallet(), depositFee), "MasterChef: cannot take deposit fee");
      }
    }

    user.amount += amount;
    pool.total += amount;
    for (uint256 i; i < rewardTokens.length; i++) {
      address token = rewardTokens[i];
      uint256 accTokenPerShare = pool.accTokenPerShares[token];
      user.rewardDebt[token] = user.amount * accTokenPerShare / ACC_TOKEN_PRECISION;
    }
    user.nextUnlockUntil = block.timestamp + pool.lockInterval;
    emit Deposit(msg.sender, pId, amount);
  }

  /**
   * @dev Withdraws token from MasterChef.
   *
   * Emits a {Withdraw} event.
   *
   * Requirements:
   *
   * - the pool exists.
   *
   * @param pId id of the pool.
   * @param amount amount of token to transfer.
   */
  function withdraw(uint256 pId, uint256 amount) external hasPool(pId) nonReentrant {
    address userAddr = msg.sender;
    require(timeleftToUnlock(pId, userAddr) == 0, "MasterChef: lock interval");

    PoolInfo storage pool = poolInfo[pId];
    UserInfo storage user = userInfo[pId][userAddr];
    require(user.amount >= amount, "Masterchef: insufficient");
    updatePool(pId);

    (, address[] memory rewardTokens,) = _payOrLockupPending(pId, userAddr);
    user.amount -= amount;
    pool.total -= amount;
    _safeTransferToken(pool.token, userAddr, amount);

    for (uint256 i; i < rewardTokens.length; i++) {
      address token = rewardTokens[i];
      uint256 accTokenPerShare = pool.accTokenPerShares[token];
      user.rewardDebt[token] = user.amount * accTokenPerShare / ACC_TOKEN_PRECISION;
    }
    user.nextUnlockUntil = block.timestamp + pool.lockInterval;

    emit Withdraw(userAddr, pId, amount);
  }

  /**
   * @dev Claims reward.
   *
   * Emits a {ClaimReward} event.
   *
   * Requirements:
   *
   * - the harvest interval is passed.
   * - the pool exits.
   *
   * @param pId id of the pool.
   */
  function claimReward(uint256 pId) external nonReentrant {
    updatePool(pId);
    (bool locked,,) = _payOrLockupPending(pId, msg.sender);
    require(!locked, "MasterChef: harvest interval");
  }

  /**
   * @dev See {MasterChef-claimReward}.
   */
  function claimRewards(uint256[] calldata pIds) external nonReentrant {
    for (uint256 i; i < pIds.length; i++) {
      updatePool(pIds[i]);
      _payOrLockupPending(pIds[i], msg.sender);
    }
  }

  /**
   * @dev Returns the timeleft to harvest.
   *
   * Requirements:
   *
   * - the pool exists.
   *
   * @param pId id of the pool.
   * @param userAddr address of the user.
   */
  function timeleftToHarvest(uint256 pId, address userAddr) public view hasPool(pId) returns (uint256) {
    UserInfo storage user = userInfo[pId][userAddr];
    return user.nextHarvestUntil - Math.min(block.timestamp, user.nextHarvestUntil);
  }

  /**
   * @dev Returns the timeleft to unlock.
   *
   * Requirements:
   *
   * - the pool exists.
   *
   * @param pId id of the pool.
   * @param userAddr address of the user.
   */
  function timeleftToUnlock(uint256 pId, address userAddr) public view hasPool(pId) returns (uint256) {
    UserInfo storage user = userInfo[pId][userAddr];
    return user.nextUnlockUntil - Math.min(block.timestamp, user.nextUnlockUntil);
  }

  /**
   * @dev Safe token transfer function, just in case if rounding error causes pool to not have enough tokens.
   *
   * @param token the token address to transfer.
   * @param to recipient address.
   * @param amount amount to transfer.
   */
  function _safeTransferToken(IERC20 token, address to, uint256 amount) private returns (uint256 realAmount) {
    if (token == cssToken) {
      realAmount = Math.min(amount, token.balanceOf(address(tokenVesting)));
      require(token.transferFrom(address(tokenVesting), to, realAmount), "MasterChef: cannot transfer fund from token vesting");
      return realAmount;
    }

    realAmount = Math.min(amount, token.balanceOf(address(this)));
    require(token.transfer(to, realAmount), "MasterChef: cannot transfer token");
  }

  /**
   * @dev Pay or lockup pending Zyber.
   *
   * Emits a {ClaimReward} event or a {LockReward} event.
   *
   * Requirements:
   *
   * @param pId id of the pool.
   * @param userAddr address of the user.
   */

  function _payOrLockupPending(uint256 pId, address userAddr)
    internal
    hasPool(pId)
    returns (bool locked, address[] memory rewardTokens, uint256[] memory values)
  {
    locked = timeleftToHarvest(pId, userAddr) > 0;

    PoolInfo storage pool = poolInfo[pId];
    UserInfo storage user = userInfo[pId][userAddr];

    rewardTokens = pool.rewardTokens;
    values = new uint256[](rewardTokens.length);

    for (uint256 i; i < rewardTokens.length; i++) {
      address token = rewardTokens[i];
      uint256 accTokenPerShare = pool.accTokenPerShares[token];
      uint256 pending = user.amount * accTokenPerShare / ACC_TOKEN_PRECISION - user.rewardDebt[token];

      if (!locked) {
        pending += user.lockedUp[token];
        delete user.lockedUp[token];
        values[i] = _safeTransferToken(IERC20(token), userAddr, pending);
        user.nextHarvestUntil = block.timestamp + pool.harvestInterval;
      } else {
        user.lockedUp[token] += pending;
        values[i] = pending;
      }

      user.rewardDebt[token] = user.amount * accTokenPerShare / ACC_TOKEN_PRECISION;
    }

    if (!locked) {
      emit ClaimReward(pId, userAddr, rewardTokens, values);
    } else {
      emit LockReward(pId, userAddr, rewardTokens, values);
    }
  }

  /**
   * @dev Returns reward multiplier over.
   *
   * @param startTime the timestamp that starts the pool.
   * @param lastRewardTime the last timestamp that distribution occurs.
   */
  function _getPassedDuration(uint256 startTime, uint256 lastRewardTime) private view returns (uint256) {
    return block.timestamp - Math.min(block.timestamp, Math.max(startTime, lastRewardTime));
  }

  /**
   * @dev Creates a token pool.
   *
   * Emits a {AddPool} event.
   *
   * Requirements:
   *
   * - the array lengths are equal.
   * - the pool exists.
   *
   * @param token the token to deposit to the pool.
   * @param startTime the timestamp to start distribute reward.
   * @param rewardTokens address list of token to distribute reward.
   * @param allocPoints how many allocation points assigned to the reward tokens.
   *
   * @return pId id of the pool.
   */
  function _createPool(
    IERC20 token,
    uint256 startTime,
    uint256 lockInterval,
    uint256 depositFeePercent,
    uint256 harvestInterval,
    address[] calldata rewardTokens,
    uint256[] calldata allocPoints
  ) private returns (uint256 pId) {
    require(rewardTokens.length > 0 && rewardTokens.length == allocPoints.length, "MasterChef: array length");
    require(lockInterval <= MAXIMUM_LOCK_INTERVAL, "MasterChef: invalid lockInterval");
    require(depositFeePercent <= MAXIMUM_DEPOSIT_FEE_RATE, "MasterChef: invalid depositFeePercent");
    require(harvestInterval <= MAXIMUM_HARVEST_INTERVAL, "MasterChef: invalid harvestInterval");

    pId = poolInfo.length;
    PoolInfo storage pool = poolInfo.push();
    pool.token = token;
    pool.startTime = startTime;
    pool.lockInterval = lockInterval;
    pool.depositFeePercent = depositFeePercent;
    pool.harvestInterval = harvestInterval;
    for (uint256 i; i < rewardTokens.length; i++) {
      address tokenAddr = rewardTokens[i];
      require(Address.isContract(tokenAddr), "MasterChef: reward must be a token");
      pool.rewardTokens.push(tokenAddr);
      pool.allocPoints[tokenAddr] = allocPoints[i];
      totalAllocPoints[tokenAddr] += allocPoints[i];
    }

    emit AddPool(pId, token, startTime, lockInterval, depositFeePercent, harvestInterval, rewardTokens, allocPoints);
  }
}

/*
@@@@@@@@@@@@@@@@@@@@@@@@@@@@&#G5J?7!~~~::::::::::::::::~^^^:::::^:G@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@#GY7~:.                                    5@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@#P?^.                                          5@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@#Y!.                    ~????????????????????????7B@@@@@@@@@@@@@
@@@@@@@@@@@@@&P!.                       5@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@&Y:                          5@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@&Y:                      .::^~^7YYYYYYYYYYYYYYYYYYYYYYYYY#@@@@@@@@@@@@@
@@@@@@@@P:                  .^7YPB#&@@@&.                         5@@@@@@@@@@@@@
@@@@@@&7                 :?P#@@@@@@@@@@&.                         5@@@@@@@@@@@@@
@@@@@B:               .7G&@@@@@@@@@&#BBP.                         5@@@@@@@@@@@@@
@@@@G.              .J#@@@@@@@&GJ!^:.                             5@@@@@@@@@@@@@
@@@G.              7#@@@@@@#5~.                                   5@@@@@@@@@@@@@
@@#.             :P@@@@@@#?.                                      5@@@@@@@@@@@@@
@@~             :#@@@@@@J.       .~JPGBBBBBBBBBBBBBBBBBBBBBBBBBBBB&@@@@@@@@@@@@@
@5             .#@@@@@&~       !P&@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@~             P@@@@@&^      ^G@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
B             ~@@@@@@7      ^&@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
5             5@@@@@#      .#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
Y   ..     .. P#####5      7@@@@@@@@@@@@@@@@@@@@@@@@&##########################&
@############B:    .       !@@@@@@@@@@@@@@@@@@@@@@@@5            ..            7
@@@@@@@@@@@@@@:            .#@@@@@@@@@@@@@@@@@@@@@@@~                          7
@@@@@@@@@@@@@@J             ~&@@@@@@@@@@@@@@@@@@@@@?       ......              5
@@@@@@@@@@@@@@#.             ^G@@@@@@@@@@@@@@@@@@#!      .G#####G.            .#
@@@@@@@@@@@@@@@P               !P&@@@@@@@@@@@@@G7.      :G@@@@@@~             ?@
@@@@@@@@@@@@@@@@5                :!JPG####BPY7:        7#@@@@@&!             :#@
@@@@@@@@@@@@@@@@@P:                   ....           !B@@@@@@#~              P@@
@@@@@@@@@@@@@@@@@@#!                             .^J#@@@@@@@Y.              J@@@
@@@@@@@@@@@@@@@@@@@@G~                      .^!JP#@@@@@@@&5^               Y@@@@
@@@@@@@@@@@@@@@@@@@@@@G7.               ?BB#&@@@@@@@@@@#J:                5@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@&P7:            5@@@@@@@@@@&GJ~.                ^B@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@B5?~:.      5@@@@&#G5?~.                  .Y@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@#BGP5YJ~~~^^..                      ?#@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@&.                         .?B@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@&.                       ^Y&@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@&.                    ^JB@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@&.                :!5#@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@&.         ..^!JP#@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@&~::^~!7?5PB&@@@@@@@@@@@@@@@@@@@@@@@@@@@@*/

