// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import {KSMath} from "./KSMath.sol";
import {IKyberSwapElasticLM} from "./IKyberSwapElasticLM.sol";
import {IKSElasticLMHelper} from "./IKSElasticLMHelper.sol";
import {IBasePositionManager} from "./IBasePositionManager.sol";
import {IPoolStorage} from "./IPoolStorage.sol";
import {IERC721} from "./IERC721.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {IERC20Metadata} from "./IERC20Metadata.sol";
import {EnumerableSet} from "./EnumerableSet.sol";
import {ReentrancyGuard} from "./ReentrancyGuard.sol";

contract KyberSwapElasticLM is IKyberSwapElasticLM, ReentrancyGuard {
  using EnumerableSet for EnumerableSet.UintSet;
  using SafeERC20 for IERC20Metadata;
  using KSMath for uint256;

  IERC721 public immutable nft;
  IKSElasticLMHelper private helper;

  address public admin;
  mapping(address => bool) public operators; // address => bool

  uint256 internal constant PRECISION = 1e12;

  uint256 public poolLength;

  // pId => Pool info
  mapping(uint256 => LMPoolInfo) public pools;

  // nftId => Position info
  mapping(uint256 => PositionInfo) public positions;

  // nftId => pId => Stake info
  mapping(uint256 => mapping(uint256 => StakeInfo)) public stakes;

  // nftId => list of joined pools
  mapping(uint256 => EnumerableSet.UintSet) internal joinedPools;

  // user address => set of nft id which user already deposit into LM contract
  mapping(address => EnumerableSet.UintSet) private depositNFTs;

  mapping(uint256 => bool) public isEmergencyWithdrawnNFT;

  bool public emergencyEnabled;

  modifier isAdmin() {
    require(msg.sender == admin, 'forbidden');
    _;
  }

  modifier isOperator() {
    require(operators[msg.sender], 'forbidden');
    _;
  }

  modifier checkLength(uint256 a, uint256 b) {
    require(a == b, 'invalid length');
    _;
  }

  constructor(IERC721 _nft) {
    nft = _nft;
    admin = msg.sender;
    operators[msg.sender] = true;
  }

  /**
   * EXTERNAL FUNCTIONS *************************
   */

  /**
   * @dev receive native reward token
   */
  receive() external payable {}

  function transferAdmin(address _admin) external isAdmin {
    admin = _admin;

    emit TransferAdmin(_admin);
  }

  function updateOperator(address user, bool grantOrRevoke) external isAdmin {
    operators[user] = grantOrRevoke;

    emit UpdateOperator(user, grantOrRevoke);
  }

  /**
   * @dev Set emergencyEnabled flag to true
   */
  function emergencyEnable() public isAdmin {
    require(!emergencyEnabled, 'Invalid value');
    emergencyEnabled = true;
    emit EmergencyEnabled();
  }

  function updateHelper(IKSElasticLMHelper _helper) external isAdmin {
    helper = _helper;

    emit LMHelperUpdated(_helper);
  }

  /**
   * @dev Add a new LM pool
   * @param poolAddress Pool address
   * @param startTime Start time of the pool
   * @param endTime End time of the pool
   * @param rewardTokens List of ERC20 reward tokens
   * @param rewardAmounts List of total reward amount for each token
   * @param feeTarget Fee target of the pool
   */
  function addPool(
    address poolAddress,
    uint32 startTime,
    uint32 endTime,
    address[] calldata rewardTokens,
    uint256[] calldata rewardAmounts,
    uint256 feeTarget
  ) external override isOperator checkLength(rewardTokens.length, rewardAmounts.length) {
    require(startTime >= _getBlockTime() && endTime > startTime, 'addPool: invalid times');
    uint256 pId = poolLength; // save gas
    LMPoolInfo storage pool = pools[pId];

    pool.poolAddress = poolAddress;
    pool.startTime = startTime;
    pool.endTime = endTime;
    pool.totalSecondsClaimed = 0;
    pool.feeTarget = feeTarget;

    for (uint256 i = 0; i < rewardTokens.length; i++) {
      pool.rewards.push(RewardData(rewardTokens[i], rewardAmounts[i]));
    }
    poolLength++;
    emit AddPool(pId, poolAddress, startTime, endTime, feeTarget);
  }

  /**
   * @dev Renew a pool to start another LM program
   * @param pId Pool id to be renewed
   * @param startTime Start time of the pool
   * @param endTime End time of the pool
   * @param rewardAmounts List of total reward amount for each token
   * @param feeTarget Fee target of the pool
   */
  function renewPool(
    uint256 pId,
    uint32 startTime,
    uint32 endTime,
    uint256[] calldata rewardAmounts,
    uint256 feeTarget
  ) external override isOperator {
    LMPoolInfo storage pool = pools[pId];

    // check if pool has not started or already ended
    require(
      pool.startTime > _getBlockTime() || pool.endTime < _getBlockTime(),
      'renew: invalid pool state'
    );
    require(pool.rewards.length == rewardAmounts.length, 'renew: invalid length');
    // check input startTime and endTime
    require(startTime > _getBlockTime() && endTime > startTime, 'renew: invalid times');
    // check pool has stakes
    require(pool.numStakes == 0, 'renew: pool has stakes');

    pool.startTime = startTime;
    pool.endTime = endTime;
    pool.totalSecondsClaimed = 0;
    pool.feeTarget = feeTarget;

    for (uint256 i = 0; i < rewardAmounts.length; ++i) {
      pool.rewards[i].rewardUnclaimed = rewardAmounts[i];
    }
    emit RenewPool(pId, startTime, endTime, feeTarget);
  }

  /**
   * @dev Deposit NFTs into the pool
   * @param nftIds List of NFT ids from BasePositionManager
   *
   */
  function deposit(uint256[] calldata nftIds) external override {
    address sender = msg.sender;
    // save gas
    bool _emergencyEnabled = emergencyEnabled;
    // save gas

    for (uint256 i = 0; i < nftIds.length; i++) {
      require(!_emergencyEnabled || !isEmergencyWithdrawnNFT[nftIds[i]], 'Not allowed to deposit');
      positions[nftIds[i]].owner = sender;
      require(depositNFTs[sender].add(nftIds[i]), 'Fail to add depositNFTs');
      nft.transferFrom(sender, address(this), nftIds[i]);
      emit Deposit(sender, nftIds[i]);
    }
  }

  /**
   * @dev Withdraw NFTs, must exit all pools before call
   * @param nftIds List of NFT ids from BasePositionManager
   */
  function withdraw(uint256[] calldata nftIds) external override {
    address sender = msg.sender;
    for (uint256 i = 0; i < nftIds.length; ++i) {
      PositionInfo storage position = positions[nftIds[i]];
      require(position.owner == sender, 'withdraw: not owner');
      require(joinedPools[nftIds[i]].length() == 0, 'withdraw: not exited yet');
      delete positions[nftIds[i]];
      require(depositNFTs[sender].remove(nftIds[i]), 'Fail to remove depositNFTs');
      nft.transferFrom(address(this), sender, nftIds[i]);
      emit Withdraw(sender, nftIds[i]);
    }
  }

  /**
   * @dev Emergency withdraw NFT position, will not receive any reward
   * @param nftIds NFT id from BasePositionManager
   */
  function emergencyWithdraw(uint256[] calldata nftIds) external {
    address sender = msg.sender;
    // save gas
    bool _emergencyEnabled = emergencyEnabled;

    for (uint256 i = 0; i < nftIds.length; ++i) {
      PositionInfo storage position = positions[nftIds[i]];
      require(position.owner == sender, 'withdraw: not owner');

      isEmergencyWithdrawnNFT[nftIds[i]] = true;
      uint256[] memory values = joinedPools[nftIds[i]].values();
      for (uint256 j = 0; j < values.length; ++j) {
        uint256 poolId = values[j];
        unchecked {
          pools[poolId].numStakes--;
        }
        delete stakes[nftIds[i]][poolId];
      }
      delete positions[nftIds[i]];

      if (!_emergencyEnabled) {
        require(depositNFTs[sender].remove(nftIds[i]), 'Fail to remove depositNFTs');
        for (uint256 j = 0; j < values.length; ++j) {
          uint256 poolId = values[j];
          require(joinedPools[nftIds[i]].remove(poolId), 'Fail to remove joinedPools');
        }
      }

      nft.transferFrom(address(this), sender, nftIds[i]);
      emit EmergencyWithdraw(sender, nftIds[i]);
    }
  }

  /**
   * @dev Emergency withdraw funds from contract, only admin can call this function
   * @param rewards List of ERC20 tokens
   * @param amounts List of amounts to be withdrawn
   */
  function emergencyWithdrawForOwner(
    address[] calldata rewards,
    uint256[] calldata amounts
  ) external override isAdmin checkLength(rewards.length, amounts.length) {
    for (uint256 i = 0; i < rewards.length; ++i) {
      _transferReward(rewards[i], msg.sender, amounts[i]);
      emit EmergencyWithdrawForOwner(rewards[i], amounts[i]);
    }
  }

  /**
   * @dev Join pools
   * @param pId pool id to join
   * @param nftIds nfts to join
   * @param liqs list liquidity value to join each nft
   *
   */
  function join(
    uint256 pId,
    uint256[] calldata nftIds,
    uint256[] calldata liqs
  ) external nonReentrant checkLength(nftIds.length, liqs.length) {
    require(poolLength > pId, 'Pool not exists');
    LMPoolInfo storage pool = pools[pId];
    require(pool.startTime <= _getBlockTime() && _getBlockTime() < pool.endTime, 'Invalid time');
    for (uint256 i = 0; i < nftIds.length; ++i) {
      require(positions[nftIds[i]].owner == msg.sender, 'Not owner');
      positions[nftIds[i]].liquidity = helper.getLiq(address(nft), nftIds[i]);
      StakeInfo storage stake = stakes[nftIds[i]][pId];
      if (stake.liquidity == 0) {
        _join(nftIds[i], pId, liqs[i], pool);
      } else {
        _sync(nftIds[i], pId, liqs[i], pool);
      }
    }
  }

  /**
   * @dev Exit from pools
   * @param pId pool ids to exit
   * @param nftIds list nfts id
   * @param liqs list liquidity value to exit from each nft
   *
   */
  function exit(
    uint256 pId,
    uint256[] calldata nftIds,
    uint256[] calldata liqs
  ) external nonReentrant checkLength(nftIds.length, liqs.length) {
    require(poolLength > pId, 'Pool not exists');
    for (uint256 i = 0; i < nftIds.length; ++i) {
      _exit(nftIds[i], pId, liqs[i], true);
    }
  }

  /**
   * @dev Claim rewards for a list of pools for a list of nft positions
   * @param nftIds List of NFT ids to harvest
   * @param datas List of pool ids to harvest for each nftId, encoded into bytes
   */
  function harvestMultiplePools(
    uint256[] calldata nftIds,
    bytes[] calldata datas
  ) external nonReentrant checkLength(nftIds.length, datas.length) {
    for (uint256 i; i < nftIds.length; ++i) {
      require(positions[nftIds[i]].owner == msg.sender, 'harvest: not owner');
      HarvestData memory data = abi.decode(datas[i], (HarvestData));
      for (uint256 j; j < data.pIds.length; ++j) {
        _harvest(nftIds[i], data.pIds[j]);
      }
    }
  }

  /**
   * @dev remove liquidity from elastic for a list of nft position, also update on farm
   * @param nftId to remove
   * @param liquidity liquidity amount to remove from nft
   * @param amount0Min expected min amount of token0 should receive
   * @param amount1Min expected min amount of token1 should receive
   * @param deadline deadline of this tx
   * @param claimFeeAndRewards also claim LP Fee and farm rewards
   */
  function removeLiquidity(
    uint256 nftId,
    uint128 liquidity,
    uint256 amount0Min,
    uint256 amount1Min,
    uint256 deadline,
    bool[2] calldata claimFeeAndRewards
  ) external nonReentrant {
    require(!emergencyEnabled, 'removeLiquidity: not allowed');

    require(block.timestamp <= deadline, 'removeLiquidity: expired');
    require(positions[nftId].owner == msg.sender, 'removeLiquidity: not owner');

    uint256 posLiquidity = positions[nftId].liquidity;
    require(liquidity > 0 && liquidity <= posLiquidity, 'removeLiquidity: invalid liquidity');

    _removeLiquidity(nftId, liquidity, deadline);
    if (claimFeeAndRewards[0]) _claimFee(nftId, deadline, false);

    posLiquidity -= liquidity;
    positions[nftId].liquidity = posLiquidity;

    uint256[] memory poolIds = joinedPools[nftId].values();
    for (uint256 i; i < poolIds.length; ) {
      uint256 stakedLiquidity = stakes[nftId][poolIds[i]].liquidity;
      uint256 deltaLiq = stakedLiquidity > posLiquidity ? stakedLiquidity - posLiquidity : 0;

      if (deltaLiq > 0) _exit(nftId, poolIds[i], deltaLiq, claimFeeAndRewards[1]);

      unchecked {
        ++i;
      }
    }

    (address token0, address token1) = helper.getPair(address(nft), nftId);
    _transferTokens(token0, token1, amount0Min, amount1Min, msg.sender);
  }

  /**
   * @dev Claim fee from elastic for a list of nft positions
   * @param nftIds List of NFT ids to claim
   * @param amount0Min expected min amount of token0 should receive
   * @param amount1Min expected min amount of token1 should receive
   * @param poolAddress address of Elastic pool of those token
   * @param deadline deadline of this tx
   */
  function claimFee(
    uint256[] calldata nftIds,
    uint256 amount0Min,
    uint256 amount1Min,
    address poolAddress,
    uint256 deadline
  ) external nonReentrant {
    require(!emergencyEnabled, 'claimFee: not allowed');
    require(block.timestamp <= deadline, 'claimFee: expired');

    uint256 length = nftIds.length;
    (address token0, address token1) = (
      address(IPoolStorage(poolAddress).token0()),
      address(IPoolStorage(poolAddress).token1())
    );

    for (uint256 i; i < length; ) {
      require(positions[nftIds[i]].owner == msg.sender, 'claimFee: not owner');

      (address nftToken0, address nftToken1) = helper.getPair(address(nft), nftIds[i]);
      require(nftToken0 == token0 && nftToken1 == token1, 'claimFee: token pair not match');

      _claimFee(nftIds[i], deadline, true);

      unchecked {
        ++i;
      }
    }

    _transferTokens(token0, token1, amount0Min, amount1Min, msg.sender);
  }

  function getJoinedPools(uint256 nftId) external view returns (uint256[] memory poolIds) {
    uint256 length = joinedPools[nftId].length();
    poolIds = new uint256[](length);
    for (uint256 i = 0; i < length; ++i) {
      poolIds[i] = joinedPools[nftId].at(i);
    }
  }

  function getJoinedPoolsInRange(
    uint256 nftId,
    uint256 fromIndex,
    uint256 toIndex
  ) external view returns (uint256[] memory poolIds) {
    require(fromIndex <= toIndex, 'fromIndex > toIndex');
    require(toIndex < joinedPools[nftId].length(), 'toIndex >= length');
    poolIds = new uint256[](toIndex - fromIndex + 1);
    for (uint256 index = fromIndex; index <= toIndex; ++index) {
      poolIds[index - fromIndex] = joinedPools[nftId].at(index);
    }
  }

  function getUserInfo(
    uint256 nftId,
    uint256 pId
  )
    external
    view
    returns (uint256 liquidity, uint256[] memory rewardPending, uint256[] memory rewardLast)
  {
    LMPoolInfo storage pool = pools[pId];
    StakeInfo storage stake = stakes[nftId][pId];

    require(stake.liquidity > 0, 'getUserInfo: not joined yet');

    rewardPending = new uint256[](pool.rewards.length);
    rewardLast = new uint256[](pool.rewards.length);

    RewardCalculationData memory data = getRewardCalculationData(nftId, pId);
    for (uint256 i = 0; i < pool.rewards.length; ++i) {
      uint256 rewardHarvest = _calculateRewardHarvest(
        stake.liquidity,
        pool.rewards[i].rewardUnclaimed,
        data.totalSecondsUnclaimed,
        data.secondsPerLiquidity
      );
      uint256 rewardCollected = _calculateRewardCollected(
        stake.rewardHarvested[i] + rewardHarvest,
        data.vestingVolume,
        stake.rewardLast[i]
      );
      rewardPending[i] = stake.rewardPending[i] + rewardCollected;
      rewardLast[i] = stake.rewardLast[i];
    }
    liquidity = stake.liquidity;
  }

  function getPoolInfo(
    uint256 pId
  )
    external
    view
    returns (
      address poolAddress,
      uint32 startTime,
      uint32 endTime,
      uint256 totalSecondsClaimed,
      uint256 feeTarget,
      uint256 numStakes,
      //index reward => reward data
      address[] memory rewardTokens,
      uint256[] memory rewardUnclaimeds
    )
  {
    LMPoolInfo storage pool = pools[pId];

    poolAddress = pool.poolAddress;
    startTime = pool.startTime;
    endTime = pool.endTime;
    totalSecondsClaimed = pool.totalSecondsClaimed;
    feeTarget = pool.feeTarget;
    numStakes = pool.numStakes;

    uint256 length = pool.rewards.length;
    rewardTokens = new address[](length);
    rewardUnclaimeds = new uint256[](length);
    for (uint256 i = 0; i < length; ++i) {
      rewardTokens[i] = pool.rewards[i].rewardToken;
      rewardUnclaimeds[i] = pool.rewards[i].rewardUnclaimed;
    }
  }

  function getDepositedNFTs(address user) external view returns (uint256[] memory listNFTs) {
    listNFTs = depositNFTs[user].values();
  }

  /**
   * INTERNAL FUNCTIONS *************************
   */
  /**
   * @dev join pool first time
   * @param nftId NFT id to join
   * @param pId pool id to join
   * @param liq liquidity amount to join
   * @param pool LM pool
   */
  function _join(uint256 nftId, uint256 pId, uint256 liq, LMPoolInfo storage pool) internal {
    PositionInfo storage position = positions[nftId];
    StakeInfo storage stake = stakes[nftId][pId];
    require(helper.checkPool(pool.poolAddress, address(nft), nftId), 'join: invalid pool');
    require(liq != 0 && liq <= position.liquidity, 'join: invalid liq');

    stake.secondsPerLiquidityLast = helper.getActiveTime(pool.poolAddress, address(nft), nftId);
    stake.rewardLast = new uint256[](pool.rewards.length);
    stake.rewardPending = new uint256[](pool.rewards.length);
    stake.rewardHarvested = new uint256[](pool.rewards.length);
    if (pool.feeTarget != 0) {
      stake.feeFirst = helper.getSignedFee(address(nft), nftId);
    }
    stake.liquidity = liq;
    pool.numStakes++;

    require(joinedPools[nftId].add(pId), 'Fail to add joinedPools');

    emit Join(nftId, pId, liq);
  }

  /**
   * @dev Increase liquidity in pool
   * @param nftId NFT id to sync
   * @param pId pool id to sync
   * @param liq liquidity amount to increase
   * @param pool LM pool
   */
  function _sync(uint256 nftId, uint256 pId, uint256 liq, LMPoolInfo storage pool) internal {
    PositionInfo storage position = positions[nftId];
    StakeInfo storage stake = stakes[nftId][pId];

    require(liq != 0 && liq + stake.liquidity <= position.liquidity, 'sync: invalid liq');

    RewardCalculationData memory data = getRewardCalculationData(nftId, pId);

    for (uint256 i = 0; i < pool.rewards.length; ++i) {
      uint256 rewardHarvest = _calculateRewardHarvest(
        stake.liquidity,
        pool.rewards[i].rewardUnclaimed,
        data.totalSecondsUnclaimed,
        data.secondsPerLiquidity
      );

      if (rewardHarvest != 0) {
        stake.rewardHarvested[i] += rewardHarvest;
        pool.rewards[i].rewardUnclaimed -= rewardHarvest;
      }

      uint256 rewardCollected = _calculateRewardCollected(
        stake.rewardHarvested[i],
        data.vestingVolume,
        stake.rewardLast[i]
      );

      if (rewardCollected != 0) {
        stake.rewardLast[i] += rewardCollected;
        stake.rewardPending[i] += rewardCollected;
      }
    }

    pool.totalSecondsClaimed += data.secondsClaim;
    stake.secondsPerLiquidityLast = data.secondsPerLiquidityNow;
    stake.feeFirst = _calculateFeeFirstAfterJoin(
      stake.feeFirst,
      data.feeNow,
      pool.feeTarget,
      stake.liquidity,
      liq,
      nftId
    );
    stake.liquidity += liq;
    emit SyncLiq(nftId, pId, liq);
  }

  /**
   * @dev Exit pool
   * @param nftId NFT id to exit
   * @param pId pool id to exit
   * @param liq liquidity amount to exit
   * @param claimReward transfer reward or not
   */
  function _exit(uint256 nftId, uint256 pId, uint256 liq, bool claimReward) internal {
    LMPoolInfo storage pool = pools[pId];
    address pOwner = positions[nftId].owner;
    StakeInfo storage stake = stakes[nftId][pId];

    require(
      pOwner == msg.sender || (_getBlockTime() > pool.endTime && operators[msg.sender]),
      'exit: not owner or pool not ended'
    );

    require(liq != 0 && liq <= stake.liquidity, 'exit: invalid liq');

    uint256 liquidityOld = stake.liquidity;
    uint256 liquidityNew = liquidityOld - liq;
    RewardCalculationData memory data = getRewardCalculationData(nftId, pId);

    pool.totalSecondsClaimed += data.secondsClaim;
    stake.secondsPerLiquidityLast = data.secondsPerLiquidityNow;
    stake.liquidity = liquidityNew;
    for (uint256 i = 0; i < pool.rewards.length; ++i) {
      uint256 rewardHarvest = _calculateRewardHarvest(
        liquidityOld,
        pool.rewards[i].rewardUnclaimed,
        data.totalSecondsUnclaimed,
        data.secondsPerLiquidity
      );

      if (rewardHarvest != 0) {
        stake.rewardHarvested[i] += rewardHarvest;
        pool.rewards[i].rewardUnclaimed -= rewardHarvest;
      }

      uint256 rewardCollected = _calculateRewardCollected(
        stake.rewardHarvested[i],
        data.vestingVolume,
        stake.rewardLast[i]
      );

      uint256 rewardPending = stake.rewardPending[i];
      if (rewardCollected != 0) {
        stake.rewardLast[i] += rewardCollected;
        rewardPending += rewardCollected;
      }

      if (claimReward) {
        stake.rewardPending[i] = 0;
        _transferReward(pool.rewards[i].rewardToken, pOwner, rewardPending);
        emit Harvest(nftId, pOwner, pool.rewards[i].rewardToken, rewardPending);
      } else {
        stake.rewardPending[i] = rewardPending;
      }
    }
    if (liquidityNew == 0) {
      delete stakes[nftId][pId];
      pool.numStakes--;

      require(joinedPools[nftId].remove(pId), 'Fail to remove joinedPools');
    }
    emit Exit(msg.sender, nftId, pId, liq);
  }

  /**
   * @dev Harvest reward
   * @param nftId NFT id to harvest
   * @param pId pool id to harvest
   */
  function _harvest(uint256 nftId, uint256 pId) internal {
    require(poolLength > pId, 'Pool not exists');
    LMPoolInfo storage pool = pools[pId];
    address pOwner = positions[nftId].owner;
    StakeInfo storage stake = stakes[nftId][pId];

    require(stake.liquidity > 0, 'harvest: not joined yet');

    RewardCalculationData memory data = getRewardCalculationData(nftId, pId);

    pool.totalSecondsClaimed += data.secondsClaim;
    stake.secondsPerLiquidityLast = data.secondsPerLiquidityNow;
    for (uint256 i = 0; i < pool.rewards.length; ++i) {
      uint256 rewardHarvest = _calculateRewardHarvest(
        stake.liquidity,
        pool.rewards[i].rewardUnclaimed,
        data.totalSecondsUnclaimed,
        data.secondsPerLiquidity
      );

      if (rewardHarvest != 0) {
        stake.rewardHarvested[i] += rewardHarvest;
        pool.rewards[i].rewardUnclaimed -= rewardHarvest;
      }

      uint256 rewardCollected = _calculateRewardCollected(
        stake.rewardHarvested[i],
        data.vestingVolume,
        stake.rewardLast[i]
      );

      uint256 rewardPending = stake.rewardPending[i] + rewardCollected;
      if (rewardPending != 0) {
        if (rewardCollected != 0) {
          stake.rewardLast[i] += rewardCollected;
        }
        stake.rewardPending[i] = 0;
        _transferReward(pool.rewards[i].rewardToken, pOwner, rewardPending);
        emit Harvest(nftId, pOwner, pool.rewards[i].rewardToken, rewardPending);
      }
    }
  }

  /**
   * @dev transfer reward
   */
  function _transferReward(address _token, address _account, uint256 _amount) internal {
    if (_token == address(0)) {
      (bool success, ) = payable(_account).call{value: _amount}('');
      require(success, 'transfer reward token failed');
    } else {
      IERC20Metadata(_token).safeTransfer(_account, _amount);
    }
  }

  /// @dev remove liquidiy of nft from posManager
  /// @param nftId nft's id
  /// @param liquidity liquidity amount to remove
  /// @param deadline removeLiquidity deadline
  function _removeLiquidity(uint256 nftId, uint128 liquidity, uint256 deadline) internal {
    IBasePositionManager.RemoveLiquidityParams memory removeLiq = IBasePositionManager
      .RemoveLiquidityParams({
        tokenId: nftId,
        liquidity: liquidity,
        amount0Min: 0,
        amount1Min: 0,
        deadline: deadline
      });

    IBasePositionManager(address(nft)).removeLiquidity(removeLiq);
  }

  /// @dev claim fee of nft from posManager
  /// @param nftId nft's id
  /// @param deadline claimFee deadline
  /// @param syncFee is need to sync new fee or not
  function _claimFee(uint256 nftId, uint256 deadline, bool syncFee) internal {
    if (syncFee) {
      IBasePositionManager(address(nft)).syncFeeGrowth(nftId);
    }

    IBasePositionManager.BurnRTokenParams memory burnRToken = IBasePositionManager
      .BurnRTokenParams({tokenId: nftId, amount0Min: 0, amount1Min: 0, deadline: deadline});

    IBasePositionManager(address(nft)).burnRTokens(burnRToken);
  }

  /// @dev transfer tokens from removeLiquidity (and burnRToken if any) to receiver
  /// @param token0 address of token0
  /// @param token1 address of token1
  /// @param amount0Min minimum amount of token0 should receive
  /// @param amount1Min minimum amount of token1 should receive
  /// @param receiver receiver of tokens
  function _transferTokens(
    address token0,
    address token1,
    uint256 amount0Min,
    uint256 amount1Min,
    address receiver
  ) internal {
    IBasePositionManager(address(nft)).transferAllTokens(token0, amount0Min, receiver);

    IBasePositionManager(address(nft)).transferAllTokens(token1, amount1Min, receiver);
  }

  /**
   * HELPER MATH FUNCTIONS *************************
   */
  function getRewardCalculationData(
    uint256 nftId,
    uint256 pId
  ) public view returns (RewardCalculationData memory data) {
    LMPoolInfo storage pool = pools[pId];
    StakeInfo storage stake = stakes[nftId][pId];

    data.secondsPerLiquidityNow = helper.getActiveTime(pool.poolAddress, address(nft), nftId);
    data.feeNow = helper.getSignedFeePool(pool.poolAddress, address(nft), nftId);
    data.vestingVolume = _calculateVestingVolume(data.feeNow, stake.feeFirst, pool.feeTarget);
    data.totalSecondsUnclaimed = _calculateSecondsUnclaimed(
      pool.startTime,
      pool.endTime,
      pool.totalSecondsClaimed
    );
    unchecked {
      data.secondsPerLiquidity = data.secondsPerLiquidityNow - stake.secondsPerLiquidityLast;
    }
    data.secondsClaim = stake.liquidity * data.secondsPerLiquidity;
  }

  /**
   * @dev feeFirst = (liq * max(feeNow - feeTarget, feeFirst) + liqAdd * feeNow) / liqNew
   */
  function _calculateFeeFirstAfterJoin(
    int256 feeFirst,
    int256 feeNow,
    uint256 feeTarget,
    uint256 liquidity,
    uint256 liquidityAdd,
    uint256 nftId
  ) internal view returns (int256) {
    if (feeTarget == 0) {
      return 0;
    }
    int256 feeFirstCurrent = feeNow - int256(feeTarget) < feeFirst
      ? feeFirst
      : feeNow - int256(feeTarget);
    int256 numerator = int256(liquidity) *
      feeFirstCurrent +
      int256(liquidityAdd) *
      helper.getSignedFee(address(nft), nftId);
    int256 denominator = int256(liquidity + liquidityAdd);
    return numerator / denominator;
  }

  /**
   * @dev vesting = min((feeNow - feeFirst) / feeTarget, 1)
   */
  function _calculateVestingVolume(
    int256 feeNow,
    int256 feeFirst,
    uint256 feeTarget
  ) internal pure returns (uint256) {
    if (feeTarget == 0) {
      return PRECISION;
    }
    uint256 feeInside = uint256(feeNow - feeFirst);
    return KSMath.min((feeInside * PRECISION) / feeTarget, PRECISION);
  }

  /**
   * @dev secondsUnclaimed = (max(currentTime, endTime) - startTime) - secondsClaimed
   */
  function _calculateSecondsUnclaimed(
    uint256 startTime,
    uint256 endTime,
    uint256 totalSecondsClaimed
  ) internal view returns (uint256) {
    uint256 totalSeconds = KSMath.max(_getBlockTime(), endTime) - startTime;
    uint256 totalSecondsScaled = totalSeconds * (1 << 96);
    return totalSecondsScaled > totalSecondsClaimed ? totalSecondsScaled - totalSecondsClaimed : 0;
  }

  /**
   * @dev rewardHarvested = L * rewardRate * secondsPerLiquidity
   */
  function _calculateRewardHarvest(
    uint256 liquidity,
    uint256 rewardUnclaimed,
    uint256 totalSecondsUnclaimed,
    uint256 secondsPerLiquidity
  ) internal pure returns (uint256) {
    return (liquidity * rewardUnclaimed * secondsPerLiquidity) / totalSecondsUnclaimed;
  }

  /**
   * @dev rewardCollected = Max(rewardHarvested * vestingVolume - rewardLast, 0);
   */
  function _calculateRewardCollected(
    uint256 rewardHarvested,
    uint256 vestingVolume,
    uint256 rewardLast
  ) internal pure returns (uint256) {
    uint256 rewardNow = (rewardHarvested * vestingVolume) / PRECISION;
    return rewardNow > rewardLast ? rewardNow - rewardLast : 0;
  }

  function _getBlockTime() internal view virtual returns (uint32) {
    return uint32(block.timestamp);
  }
}

