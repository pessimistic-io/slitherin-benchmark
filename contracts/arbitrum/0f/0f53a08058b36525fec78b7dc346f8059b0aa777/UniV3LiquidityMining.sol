// SPDX-License-Identifier: BUSL-1.1
// This code is made available under the terms and conditions of the Business Source License 1.1 (BUSL-1.1).
// The act of publishing this code is driven by the aim to promote transparency and facilitate its utilization for educational purposes.
//   _   _ __  ____  __
//  | | | |  \/  \ \/ /
//  | |_| | |\/| |\  /
//  |  _  | |  | |/  \
//  |_| |_|_|  |_/_/\_\
//

pragma solidity 0.8.18;

// OZs
import { Initializable } from "./Initializable.sol";
import { Ownable2StepUpgradeable } from "./Ownable2StepUpgradeable.sol";
import { IERC20Upgradeable } from "./IERC20Upgradeable.sol";
import { SafeERC20Upgradeable } from "./SafeERC20Upgradeable.sol";
import { MulticallUpgradeable } from "./MulticallUpgradeable.sol";

// Interfaces
import { INonfungiblePositionManager } from "./INonfungiblePositionManager.sol";
import { IUniswapFactory } from "./IUniswapFactory.sol";
import { IUniswapV3Pool } from "./IUniswapV3Pool.sol";
import { IUniswapSwapRouter02 } from "./IUniswapSwapRouter02.sol";

// Libs
import { NFTPositionInfo } from "./NFTPositionInfo.sol";
import { RewardMath } from "./RewardMath.sol";
import { UniswapV3Zap } from "./UniswapV3Zap.sol";

/// @title UniV3LiquidityMining - Liquidity mining contract for Uniswap V3 LP position.
/// @notice Most of the logic is taken from v3-staker contract.
/// @dev Origin core logic: https://github.com/Uniswap/v3-staker
/// @dev Read more about limitations: https://www.paradigm.xyz/2021/05/liquidity-mining-on-uniswap-v3
contract UniV3LiquidityMining is Initializable, Ownable2StepUpgradeable, MulticallUpgradeable {
  using SafeERC20Upgradeable for IERC20Upgradeable;

  IUniswapFactory public uniswapV3Factory;
  INonfungiblePositionManager public nonfungiblePositionManager;
  IUniswapSwapRouter02 public swapRouter;

  IUniswapV3Pool public incentivizedPool;
  IERC20Upgradeable public token0;
  IERC20Upgradeable public token1;

  IERC20Upgradeable public rewardToken;
  address public keeper;

  struct Incentive {
    uint256 totalRewardUnclaimed;
    uint160 totalSecondsClaimedX128;
    uint96 numberOfStakes;
    uint64 startTime;
    uint64 endTime;
  }
  Incentive[] public incentives;
  uint64 public upKeepCursor;
  uint64 public minLiquidity;
  uint64 public maxPositions;
  uint256 public activeIncentiveId;

  struct Deposit {
    address soleOwner;
    bool isStake;
    int24 tickLower;
    int24 tickUpper;
  }
  /// @dev deposits[tokenId] => Deposit
  mapping(uint256 => Deposit) public deposits;
  /// @dev array of all tokenIds
  uint256[] public tokenIds;
  address public compounder;

  struct Stake {
    uint160 secondsPerLiquidityInsideInitialX128;
    uint128 liquidity;
  }
  /// @dev stakes[tokenId][incentiveId] => Stake
  mapping(uint256 => mapping(uint256 => Stake)) public stakes;

  /// @dev rewards[owner] => uint256
  mapping(address => uint256) public rewards;

  /// Events
  event DepositedNFT(uint256 indexed tokenId, address indexed owner);
  event Concluded(uint256 indexed incentiveId, uint256 refund, address to);
  event ClaimedRewards(address indexed owner, uint256 amount);
  event ScheduledIncentive(
    uint256 indexed incentiveIndex,
    uint256 totalReward,
    uint64 startTime,
    uint64 endTime
  );
  event StakedNFT(uint256 indexed tokenId, uint256 indexed incentiveId, uint128 liquidity);
  event SetMaxPosition(uint64 prevMaxPosition, uint64 newMaxPosition);
  event SetMinLiquidity(uint64 prevMinLiquidity, uint64 newMinLiquidity);
  event SetKeeper(address prevKeeper, address newKeeper);
  event UnstakedNFT(uint256 indexed tokenId, uint256 indexed incentiveId);
  event UpKept(uint64 upKeepCursor, uint64 limit);
  event WithdrawnNFT(address indexed owner, uint256 indexed tokenId, address indexed to);
  event SetCompounder(address indexed oldCompounder, address indexed newCompounder);
  event Rollover(uint256 indexed incentiveId, uint256 rolloverAmount);

  error UniV3LiquidityMining_NotCompounder();

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize(
    IUniswapFactory _uniswapV3Factory,
    INonfungiblePositionManager _nonfungiblePositionManager,
    IUniswapSwapRouter02 _swapRouter,
    IUniswapV3Pool _incentivizedPool,
    IERC20Upgradeable _rewardToken,
    address _keeper,
    uint64 _maxPositions
  ) external initializer {
    Ownable2StepUpgradeable.__Ownable2Step_init();
    MulticallUpgradeable.__Multicall_init();

    uniswapV3Factory = _uniswapV3Factory;
    nonfungiblePositionManager = _nonfungiblePositionManager;
    swapRouter = _swapRouter;

    incentivizedPool = _incentivizedPool;
    token0 = IERC20Upgradeable(_incentivizedPool.token0());
    token1 = IERC20Upgradeable(_incentivizedPool.token1());

    rewardToken = _rewardToken;
    keeper = _keeper;
    maxPositions = _maxPositions;

    // Approve
    token0.safeApprove(address(swapRouter), type(uint256).max);
    token1.safeApprove(address(swapRouter), type(uint256).max);
    token0.safeApprove(address(nonfungiblePositionManager), type(uint256).max);
    token1.safeApprove(address(nonfungiblePositionManager), type(uint256).max);
  }

  /// @notice Set the maximum number of positions that can be deposited.
  /// @param _newMaxPositions New maximum number of positions.
  function setMaxPositions(uint64 _newMaxPositions) external onlyOwner {
    emit SetMaxPosition(maxPositions, _newMaxPositions);
    maxPositions = _newMaxPositions;
  }

  /// @notice Set the minimum liquidity for a deposit to be valid.
  /// @param _newMinLiquidity New minimum liquidity.
  function setMinLiquidity(uint64 _newMinLiquidity) external onlyOwner {
    emit SetMinLiquidity(minLiquidity, _newMinLiquidity);
    minLiquidity = _newMinLiquidity;
  }

  /// @notice Set the keeper address.
  /// @param _newKeeper New keeper address.
  function setKeeper(address _newKeeper) external onlyOwner {
    emit SetKeeper(keeper, _newKeeper);
    keeper = _newKeeper;
  }

  function setCompounder(address _compounder) external onlyOwner {
    emit SetCompounder(compounder, _compounder);
    compounder = _compounder;
  }

  /// @notice Schedule an incentive for a given time range.
  /// @param _rewards Amount of reward tokens to be distributed.
  /// @param _startTime Start time of the incentive.
  /// @param _endTime End time of the incentive.
  function scheduleIncentive(
    uint256 _rewards,
    uint64 _startTime,
    uint64 _endTime
  ) external onlyOwner {
    // Check
    require(_rewards > 0, "bad _rewards");
    require(block.timestamp <= _startTime, "bad _startTime");
    require(_startTime < _endTime, "bad _endTime");
    if (incentives.length > 0) {
      require(
        _startTime >= incentives[incentives.length - 1].endTime,
        "_startTime < last incentive endTime"
      );
    }

    // Effect
    incentives.push(
      Incentive({
        totalRewardUnclaimed: _rewards,
        totalSecondsClaimedX128: 0,
        numberOfStakes: 0,
        startTime: _startTime,
        endTime: _endTime
      })
    );

    // Interaction
    rewardToken.safeTransferFrom(msg.sender, address(this), _rewards);

    // Log
    emit ScheduledIncentive(incentives.length - 1, _rewards, _startTime, _endTime);
  }

  /// @notice Conclud an incentive. Move all unclaimed rewards to "_to".
  /// @param _incentiveId Incentive to conclude.
  /// @param _to Address to send unclaimed rewards to.
  function conclude(uint256 _incentiveId, address _to) external onlyOwner {
    // Check
    // Only allow to conclude when the incentive has ended
    require(block.timestamp >= incentives[_incentiveId].endTime, "!ended");

    Incentive storage incentive = incentives[_incentiveId];

    uint256 _refund = incentive.totalRewardUnclaimed;

    require(_refund > 0, "no refund");
    require(incentive.numberOfStakes == 0, "some staked");

    // Refund the unclaimed
    incentive.totalRewardUnclaimed = 0;
    rewardToken.safeTransfer(_to, _refund);

    emit Concluded(_incentiveId, _refund, _to);
  }

  /// @notice Up keep function to be called by the keeper. This will move all stakes to the next incentive.
  function upKeep(uint64 _maxIndex, bool rolloverRewards) external {
    require(msg.sender == keeper, "!keeper");
    require(block.timestamp >= incentives[activeIncentiveId].endTime, "!activeIncentive.ended");

    bool _hasNextIncentive = incentives.length > activeIncentiveId + 1;

    // Effect
    // Find out limit. If # NFT < _maxIndex then _maxIndex = # NFT, else _maxIndex
    _maxIndex = tokenIds.length < _maxIndex ? uint64(tokenIds.length) : _maxIndex;
    uint256 _tokenId;
    Stake memory _stakeTmp;
    // Unstake and stake to next incentive if has next incentive
    for (uint256 _i = upKeepCursor; _i < _maxIndex; _i++) {
      _tokenId = tokenIds[_i];
      // Unstake only if liquidity > 0
      _stakeTmp = stakes[_tokenId][activeIncentiveId];
      if (_stakeTmp.liquidity > 0) unstake(_tokenId);
      if (_hasNextIncentive) {
        // Stake only if liquidity == 0;
        _stakeTmp = stakes[_tokenId][activeIncentiveId + 1];
        if (_stakeTmp.liquidity == 0) _stake(activeIncentiveId + 1, _tokenId);
      }
    }

    // Update upKeepCursor. If upKeepCursor == tokenIds.length then reset upKeepCursor to 0.
    upKeepCursor = _maxIndex == tokenIds.length ? 0 : _maxIndex;

    if (_hasNextIncentive && incentives[activeIncentiveId].numberOfStakes == 0) {
      // Only move active incentive id if has next incentive and
      // no stakes left in the current incentive
      if (rolloverRewards) {
        // Get unclaimed rewards of the current incentive period
        uint256 _unclaimedRewardsFromCurrent = incentives[activeIncentiveId].totalRewardUnclaimed;
        // Roll them over to the next incentive period
        incentives[activeIncentiveId + 1].totalRewardUnclaimed += _unclaimedRewardsFromCurrent;
        emit Rollover(activeIncentiveId, _unclaimedRewardsFromCurrent);
      }
      activeIncentiveId++;
    }

    emit UpKept(upKeepCursor, _maxIndex);
  }

  /// @notice Create the token deposit if received UniV3 ERC721 and stake it to the active incentive.
  function onERC721Received(
    address,
    address _from,
    uint256 _tokenId,
    bytes calldata
  ) external returns (bytes4) {
    // Check
    // Only accept NFT from UniV3 NFT
    require(msg.sender == address(nonfungiblePositionManager), "caller !UniV3NFT");
    // Only accept if deposited NFTs <= maxPositions
    require(tokenIds.length < maxPositions, "full");

    // Effect
    // Load NFT info
    (, , , , , int24 _tickLower, int24 _tickUpper, , , , , ) = nonfungiblePositionManager.positions(
      _tokenId
    );
    // Deposit NFT
    deposits[_tokenId] = Deposit({
      soleOwner: _from,
      isStake: false,
      tickLower: _tickLower,
      tickUpper: _tickUpper
    });
    tokenIds.push(_tokenId);
    // Stake NFT to the active incentive
    _stake(activeIncentiveId, _tokenId);

    emit DepositedNFT(_tokenId, _from);

    return this.onERC721Received.selector;
  }

  /// @notice Stake NFT. Revert if not owner.
  /// @param _tokenId Token ID of the NFT.
  function stake(uint256 _tokenId) external {
    require(deposits[_tokenId].soleOwner == msg.sender || msg.sender == compounder, "!owner");
    _stake(activeIncentiveId, _tokenId);
  }

  /// @notice Perform the actual staking action.
  /// @param _incentiveId Incentive ID to stake the token to.
  /// @param _tokenId Token ID of the NFT.
  function _stake(uint256 _incentiveId, uint256 _tokenId) internal {
    // Check
    // Load incentive info
    Incentive storage incentive = incentives[_incentiveId];

    // Ensure the incentive is active
    require(block.timestamp >= incentive.startTime, "!started");
    require(block.timestamp < incentive.endTime, "ended");
    require(incentive.totalRewardUnclaimed > 0, "no rewards");

    // Ensure the token is not already staked
    require(stakes[_tokenId][_incentiveId].liquidity == 0, "already staked");

    // Load NFT's position info
    (IUniswapV3Pool _pool, int24 _tickLower, int24 _tickUpper, uint128 _liquidity) = NFTPositionInfo
      .getPositionInfo(uniswapV3Factory, nonfungiblePositionManager, _tokenId);

    // Ensure liquidity is provided to the incentivized pool
    require(_pool == incentivizedPool, "!incentivizedPool");
    // Ensure liquidity is above minimum. This to prevent griefing when migrating to a new incentive.
    require(_liquidity >= minLiquidity, "liquidity too small");

    // Effect
    incentive.numberOfStakes += 1;
    deposits[_tokenId].isStake = true;

    // Snpashot seconds per liquidity of the given position
    (, uint160 _secondsPerLiquidityInsideX128, ) = _pool.snapshotCumulativesInside(
      _tickLower,
      _tickUpper
    );
    // Store stake info
    Stake storage stake_ = stakes[_tokenId][_incentiveId];
    stake_.secondsPerLiquidityInsideInitialX128 = _secondsPerLiquidityInsideX128;
    stake_.liquidity = _liquidity;

    // Emit event
    emit StakedNFT(_tokenId, _incentiveId, _liquidity);
  }

  /// @notice Unstake the token and update rewards state.
  /// @param _tokenId Token ID of the NFT.
  function unstake(uint256 _tokenId) public {
    Deposit memory _deposit = deposits[_tokenId];
    // Allow anyone to unstake if the incentive is over, so only check
    // if msg.sender is the owner if the incentive is still active
    // or if it's compounder, let the compounder unstake to claim rewards
    if (block.timestamp < incentives[activeIncentiveId].endTime) {
      require(msg.sender == _deposit.soleOwner || msg.sender == compounder, "!owner");
    }

    Stake memory __stake = stakes[_tokenId][activeIncentiveId];
    require(__stake.liquidity > 0, "!staked");

    Incentive storage incentive = incentives[activeIncentiveId];

    deposits[_tokenId].isStake = false;
    incentive.numberOfStakes--;

    (, uint160 _secondsPerLiquidityInsideX128, ) = incentivizedPool.snapshotCumulativesInside(
      _deposit.tickLower,
      _deposit.tickUpper
    );
    (uint256 _rewards, uint160 _secondsInsideX128) = RewardMath.computeRewardAmount(
      incentive.totalRewardUnclaimed,
      incentive.totalSecondsClaimedX128,
      incentive.startTime,
      incentive.endTime,
      __stake.liquidity,
      __stake.secondsPerLiquidityInsideInitialX128,
      _secondsPerLiquidityInsideX128,
      block.timestamp
    );

    // Update incentive state
    incentive.totalSecondsClaimedX128 += _secondsInsideX128;
    incentive.totalRewardUnclaimed -= _rewards;

    // Update reward state
    rewards[_deposit.soleOwner] += _rewards;

    // Delete stake
    Stake storage stake_ = stakes[_tokenId][activeIncentiveId];
    delete stake_.secondsPerLiquidityInsideInitialX128;
    delete stake_.liquidity;

    emit UnstakedNFT(_tokenId, activeIncentiveId);
  }

  /// @notice Get the pending rewards for the given token ID.
  /// @dev If you wish to get all "unclaimedRewards" for the user,
  /// you will have to sum(getPendingRewards(tokenIdOwnedByUser)) + rewards[user].
  /// @param _tokenId Token ID of the NFT.
  function getPendingRewards(uint256 _tokenId) external view returns (uint256 _rewards) {
    Stake memory __stake = stakes[_tokenId][activeIncentiveId];
    if (__stake.liquidity == 0) {
      return 0;
    }

    Deposit memory _deposit = deposits[_tokenId];
    Incentive memory _incentive = incentives[activeIncentiveId];

    (, uint160 _secondsPerLiquidityInsideX128, ) = incentivizedPool.snapshotCumulativesInside(
      _deposit.tickLower,
      _deposit.tickUpper
    );

    (_rewards, ) = RewardMath.computeRewardAmount(
      _incentive.totalRewardUnclaimed,
      _incentive.totalSecondsClaimedX128,
      _incentive.startTime,
      _incentive.endTime,
      __stake.liquidity,
      __stake.secondsPerLiquidityInsideInitialX128,
      _secondsPerLiquidityInsideX128,
      block.timestamp
    );
  }

  /// @notice Claim rewards.
  /// @param _requestedAmount Amount of reward tokens to be claimed.
  /// @param _to Address to receive the reward tokens.
  function claim(uint256 _requestedAmount, address _to) external returns (uint256 _payOut) {
    return _claim(msg.sender, _requestedAmount, _to);
  }

  function harvestToCompounder(
    address user,
    uint256 _requestedAmount,
    address _to
  ) external returns (uint256 _payOut) {
    if (compounder != msg.sender) revert UniV3LiquidityMining_NotCompounder();
    return _claim(user, _requestedAmount, _to);
  }

  function _claim(
    address user,
    uint256 _requestedAmount,
    address _to
  ) internal returns (uint256 _payOut) {
    _payOut = rewards[user];
    if (_requestedAmount < _payOut) {
      _payOut = _requestedAmount;
    }

    rewards[user] -= _payOut;
    rewardToken.safeTransfer(_to, _payOut);

    emit ClaimedRewards(user, _payOut);
  }

  /// @notice Compound trading fee into the position.
  /// @param _tokenId Token ID of the NFT.
  function compound(uint256 _tokenId, uint128 _minLiquidity) external {
    // Check
    // Only owner can compound
    require(deposits[_tokenId].soleOwner == msg.sender, "!owner");

    // Claim trading fee + decreased liquidity
    (uint256 _amount0, uint256 _amount1) = nonfungiblePositionManager.collect(
      INonfungiblePositionManager.CollectParams({
        tokenId: _tokenId,
        recipient: address(this),
        amount0Max: type(uint128).max,
        amount1Max: type(uint128).max
      })
    );

    // Calc zap amount
    (uint256 _swapAmount, bool _zeroForOne) = UniswapV3Zap.calc(
      UniswapV3Zap.CalcParams(
        incentivizedPool,
        _amount0,
        _amount1,
        deposits[_tokenId].tickLower,
        deposits[_tokenId].tickUpper
      )
    );

    // Figure out tokenIn and tokenOut
    address _tokenIn = _zeroForOne ? address(token0) : address(token1);
    address _tokenOut = _zeroForOne ? address(token1) : address(token0);

    // Swap
    uint256 _amountOut = swapRouter.exactInputSingle(
      IUniswapSwapRouter02.ExactInputSingleParams({
        tokenIn: _tokenIn,
        tokenOut: _tokenOut,
        fee: incentivizedPool.fee(),
        recipient: address(this),
        amountIn: _swapAmount,
        amountOutMinimum: 0,
        sqrtPriceLimitX96: 0
      })
    );

    // Add liquidity
    (_amount0, _amount1) = _zeroForOne
      ? (_amount0 - _swapAmount, _amount1 + _amountOut)
      : (_amount0 + _amountOut, _amount1 - _swapAmount);

    (
      uint128 _increasedLiquidity,
      uint256 _actualAmount0,
      uint256 _actualAmount1
    ) = nonfungiblePositionManager.increaseLiquidity(
        INonfungiblePositionManager.IncreaseLiquidityParams({
          tokenId: _tokenId,
          amount0Desired: _amount0,
          amount1Desired: _amount1,
          amount0Min: 0,
          amount1Min: 0,
          deadline: block.timestamp
        })
      );
    require(_increasedLiquidity >= _minLiquidity, "slippage");

    if (_amount0 > _actualAmount0) {
      token0.safeTransfer(deposits[_tokenId].soleOwner, _amount0 - _actualAmount0);
    }
    if (_amount1 > _actualAmount1) {
      token1.safeTransfer(deposits[_tokenId].soleOwner, _amount1 - _actualAmount1);
    }
  }

  /// @notice Withdraw the NFT from the contract.
  /// @param _tokenId Token ID of the NFT.
  /// @param _index Index of the token ID in the tokenIds array.
  /// @param _to Address to receive the NFT.
  function withdraw(uint256 _tokenId, uint256 _index, address _to) external {
    // Check
    require(_to != address(0), "bad _to");
    Deposit memory _deposit = deposits[_tokenId];
    require(_deposit.soleOwner == msg.sender, "!owner");
    require(_deposit.isStake == false, "staked");
    require(tokenIds[_index] == _tokenId, "bad index");

    // Effect
    delete deposits[_tokenId];
    tokenIds[_index] = tokenIds[tokenIds.length - 1];
    tokenIds.pop();

    // Interaction
    nonfungiblePositionManager.safeTransferFrom(address(this), _to, _tokenId);

    // Log
    emit WithdrawnNFT(msg.sender, _tokenId, _to);
  }

  function getTokenIds() external view returns (uint256[] memory) {
    return tokenIds;
  }
}

