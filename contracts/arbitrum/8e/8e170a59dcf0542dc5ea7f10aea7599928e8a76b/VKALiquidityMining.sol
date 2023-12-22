// SPDX-License-Identifier: BUSL-1.1
// This code is made available under the terms and conditions of the Business Source License 1.1 (BUSL-1.1).
// The act of publishing this code is driven by the aim to promote transparency and facilitate its utilization for educational purposes.

pragma solidity 0.8.18;

import { Initializable } from "./Initializable.sol";
import { Ownable2StepUpgradeable } from "./Ownable2StepUpgradeable.sol";
import { IERC20Upgradeable } from "./IERC20Upgradeable.sol";
import { SafeERC20Upgradeable } from "./SafeERC20Upgradeable.sol";
import { MulticallUpgradeable } from "./MulticallUpgradeable.sol";

import { INonfungiblePositionManager } from "./INonfungiblePositionManager.sol";
import { IUniswapFactory } from "./IUniswapFactory.sol";
import { IUniswapV3Pool } from "./IUniswapV3Pool.sol";
import { IUniswapSwapRouter02 } from "./IUniswapSwapRouter02.sol";

import { NFTPositionInfo } from "./NFTPositionInfo.sol";
import { RewardMath } from "./RewardMath.sol";
import { UniswapV3Zap } from "./UniswapV3Zap.sol";

contract VKALiquidityMining is Initializable, Ownable2StepUpgradeable, MulticallUpgradeable {
  using SafeERC20Upgradeable for IERC20Upgradeable;

  IUniswapFactory public uniswapV3Factory;
  INonfungiblePositionManager public nonfungiblePositionManager;
  IUniswapSwapRouter02 public swapRouter;
  IUniswapV3Pool public poolIncent;

  IERC20Upgradeable public token0;
  IERC20Upgradeable public token1;
  IERC20Upgradeable public tokenReward;

  address public maintainer;

  struct Incentive {
    uint256 rewardsUnclaimed;
    uint160 secondsClaimed;
    uint96 stakes;
    uint64 startTimtestamp;
    uint64 endTimestamp;
  }

  struct Stake {
    uint160 secondsPerLiquidity;
    uint128 liquidity;
  }

  struct Deposit {
    address ownerOf;
    bool isStaked;
    int24 tickLower;
    int24 tickUpper;
  }

  Incentive[] public incent;

  uint64 public upKeepOne;
  uint64 public minLiquidity;
  uint64 public maxPos;
  uint256 public activeIncent;
  uint256[] public tokenIds;

  mapping(uint256 => Deposit) public deposits;
  mapping(uint256 => mapping(uint256 => Stake)) public stakes;
  mapping(address => uint256) public rewards;
  mapping(uint256 => uint256) public tokenPosition;

  event NFTDeposited(uint256 indexed tokenId, address indexed owner);
  event Finished(uint256 indexed incentiveId, uint256 refund, address to);
  event RewardsClaimed(address indexed owner, uint256 amount);
  event IncentiveScheduled(
    uint256 indexed incentiveIndex,
    uint256 totalReward,
    uint64 startTimtestamp,
    uint64 endTimestamp
  );
  event StakedNFT(uint256 indexed tokenId, uint256 indexed incentiveId, uint128 liquidity);
  event SetMaxPos(uint64 prevMaxPosition, uint64 newMaxPosition);
  event SetMinLiq(uint64 prevMinLiquidity, uint64 newMinLiquidity);
  event SetMaintainer(address prevmaintainer, address newmaintainer);
  event UnStakedNFT(uint256 indexed tokenId, uint256 indexed incentiveId);
  event Kept(uint64 upKeepOne, uint64 limit);
  event NFTWithdrawn(address indexed owner, uint256 indexed tokenId, address indexed to);
  event Rollover(uint256 indexed incentiveId, uint256 rolloverAmount);

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize(
    IUniswapFactory _uniswapV3Factory,
    INonfungiblePositionManager _nonfungiblePositionManager,
    IUniswapSwapRouter02 _swapRouter,
    IUniswapV3Pool _poolIncent,
    IERC20Upgradeable _tokenReward
  ) external initializer {
    Ownable2StepUpgradeable.__Ownable2Step_init();
    MulticallUpgradeable.__Multicall_init();

    uniswapV3Factory = _uniswapV3Factory;
    nonfungiblePositionManager = _nonfungiblePositionManager;
    swapRouter = _swapRouter;

    poolIncent = _poolIncent;
    token0 = IERC20Upgradeable(_poolIncent.token0());
    token1 = IERC20Upgradeable(_poolIncent.token1());

    tokenReward = _tokenReward;

    // Approve
    token0.safeApprove(address(swapRouter), type(uint256).max);
    token1.safeApprove(address(swapRouter), type(uint256).max);
    token0.safeApprove(address(nonfungiblePositionManager), type(uint256).max);
    token1.safeApprove(address(nonfungiblePositionManager), type(uint256).max);
  }

  function setMaxPos(uint64 _newmaxPos) external onlyOwner {
    maxPos = _newmaxPos;
    emit SetMaxPos(maxPos, _newmaxPos);
  }

  function setMinLiq(uint64 _newMinLiquidity) external onlyOwner {
    minLiquidity = _newMinLiquidity;
    emit SetMinLiq(minLiquidity, _newMinLiquidity);
  }

  function setMaintainer(address _newmaintainer) external onlyOwner {
    maintainer = _newmaintainer;
    emit SetMaintainer(maintainer, _newmaintainer);
  }

  function resetIncentiveStakes(uint256 _incentive) public onlyOwner {
    require(block.timestamp >= incent[_incentive].endTimestamp, "!ended");
    incent[_incentive].stakes = 0;
  }

  function incrementIncentive() public onlyOwner {
    activeIncent++;
  }

  function startIncentive(
    uint256 _rewards
    // uint64 _startTimtestamp,
    // uint64 _endTimestamp
  ) external onlyOwner {
    // Check
    // require(_rewards > 0, "bad _rewards");
    // require(block.timestamp <= _startTimtestamp, "bad _startTimtestamp");
    // require(_startTimtestamp < _endTimestamp, "bad _endTimestamp");
    // if (incent.length > 0) {
    //   require(
    //     _startTimtestamp >= incent[incent.length - 1].endTimestamp,
    //     "_startTimtestamp < last incentive endTimestamp"
    //   );
    // }

    uint64 _startTimtestamp = uint64(block.timestamp);
    uint64 _endTimestamp = uint64(block.timestamp + 30 days);
    
    // Effect
    incent.push(
      Incentive({
        rewardsUnclaimed: _rewards,
        secondsClaimed: 0,
        stakes: 0,
        startTimtestamp: _startTimtestamp,
        endTimestamp: _endTimestamp
      })
    );

    tokenReward.safeTransferFrom(msg.sender, address(this), _rewards);

    emit IncentiveScheduled(incent.length - 1, _rewards, _startTimtestamp, _endTimestamp);
  }

  function finishIncentive(uint256 _incentiveId, address _to) external onlyOwner {
    require(block.timestamp >= incent[_incentiveId].endTimestamp, "!ended");

    Incentive storage incentive = incent[_incentiveId];

    uint256 _refund = incentive.rewardsUnclaimed;

    require(_refund > 0, "no refund");
    require(incentive.stakes == 0, "some staked");

    incentive.rewardsUnclaimed = 0;
    tokenReward.safeTransfer(_to, _refund);

    emit Finished(_incentiveId, _refund, _to);
  }

  function keep(uint64 _maxIndex, bool rolloverRewards) external {
    require(msg.sender == maintainer, "!maintainer");
    require(block.timestamp >= incent[activeIncent].endTimestamp, "!activeIncentive.ended");

    bool _hasNextIncentive = incent.length > activeIncent + 1;

    _maxIndex = tokenIds.length < _maxIndex ? uint64(tokenIds.length) : _maxIndex;
    uint256 _tokenId;
    Stake memory _stakeTmp;
    Incentive storage incentive = incent[activeIncent];

    for (uint256 _i = upKeepOne; _i < _maxIndex; _i++) {
      _tokenId = tokenIds[_i];
      _stakeTmp = stakes[_tokenId][activeIncent];
      uint256 activeILiquidity = _stakeTmp.liquidity;

      if (_stakeTmp.liquidity > 0) {
        unstake(_tokenId);
      }

      if (_hasNextIncentive) {
        _stakeTmp = stakes[_tokenId][activeIncent + 1];
        if (_stakeTmp.liquidity == 0 && activeILiquidity > 0) _stake(activeIncent + 1, _tokenId);
      }
    }

    upKeepOne = _maxIndex == tokenIds.length ? 0 : _maxIndex;

    if (_hasNextIncentive && incent[activeIncent].stakes == 0) {
      if (rolloverRewards) {
        uint256 _unRewardsClaimedFromCurrent = incent[activeIncent].rewardsUnclaimed;
        incent[activeIncent + 1].rewardsUnclaimed += _unRewardsClaimedFromCurrent;
        incent[activeIncent].rewardsUnclaimed = 0;
        emit Rollover(activeIncent, _unRewardsClaimedFromCurrent);
      }
      activeIncent++;
    }

    emit Kept(upKeepOne, _maxIndex);
  }

  // View functions //
  function getIds() external view returns (uint256[] memory) {
    return tokenIds;
  }

   /// @notice Get the pending rewards for the given token ID.
  /// @dev If you wish to get all "unRewardsClaimed" for the user,
  /// you will have to sum(getPendingRewards(tokenIdOwnedByUser)) + rewards[user].
  /// @param _tokenId Token ID of the NFT.
  function pendingRewards(uint256 _tokenId) external view returns (uint256 _rewards) {
    Stake memory __stake = stakes[_tokenId][activeIncent];
    if (__stake.liquidity == 0) {
      return 0;
    }

    Deposit memory _deposit = deposits[_tokenId];
    Incentive memory _incentive = incent[activeIncent];

    (, uint160 _secondsPerLiquidityInsideX128, ) = poolIncent.snapshotCumulativesInside(
      _deposit.tickLower,
      _deposit.tickUpper
    );

    (_rewards, ) = RewardMath.computeRewardAmount(
      _incentive.rewardsUnclaimed,
      _incentive.secondsClaimed,
      _incentive.startTimtestamp,
      _incentive.endTimestamp,
      __stake.liquidity,
      __stake.secondsPerLiquidity,
      _secondsPerLiquidityInsideX128,
      block.timestamp
    );
  }

  function stake(uint256 _tokenId) external {
    require(deposits[_tokenId].ownerOf == msg.sender, "!owner");
    _stake(activeIncent, _tokenId);
  }

  function _stake(uint256 _incentiveId, uint256 _tokenId) internal {
    Incentive storage incentive = incent[_incentiveId];

    require(block.timestamp >= incentive.startTimtestamp, "!started");
    require(block.timestamp < incentive.endTimestamp, "ended");
    require(incentive.rewardsUnclaimed > 0, "no rewards");
    require(stakes[_tokenId][_incentiveId].liquidity == 0, "already staked");

    (IUniswapV3Pool _pool, int24 _tickLower, int24 _tickUpper, uint128 _liquidity) = NFTPositionInfo
      .getPositionInfo(uniswapV3Factory, nonfungiblePositionManager, _tokenId);

    require(_pool == poolIncent, "!poolIncent");
    require(_liquidity >= minLiquidity, "liquidity too small");

    incentive.stakes += 1;
    deposits[_tokenId].isStaked = true;

    (, uint160 _secondsPerLiquidityInsideX128, ) = _pool.snapshotCumulativesInside(
      _tickLower,
      _tickUpper
    );

    Stake storage stake_ = stakes[_tokenId][_incentiveId];
    stake_.secondsPerLiquidity = _secondsPerLiquidityInsideX128;
    stake_.liquidity = _liquidity;

    emit StakedNFT(_tokenId, _incentiveId, _liquidity);
  }

  function unstake(uint256 _tokenId) public {
    Deposit memory _deposit = deposits[_tokenId];
    if (block.timestamp < incent[activeIncent].endTimestamp) {
      require(msg.sender == _deposit.ownerOf, "!owner");
    }

    Stake memory __stake = stakes[_tokenId][activeIncent];
    require(__stake.liquidity > 0, "!staked");

    Incentive storage incentive = incent[activeIncent];

    deposits[_tokenId].isStaked = false;
    incentive.stakes--;

    (, uint160 _secondsPerLiquidityInsideX128, ) = poolIncent.snapshotCumulativesInside(
      _deposit.tickLower,
      _deposit.tickUpper
    );
    (uint256 _rewards, uint160 _secondsInsideX128) = RewardMath.computeRewardAmount(
      incentive.rewardsUnclaimed,
      incentive.secondsClaimed,
      incentive.startTimtestamp,
      incentive.endTimestamp,
      __stake.liquidity,
      __stake.secondsPerLiquidity,
      _secondsPerLiquidityInsideX128,
      block.timestamp
    );

    incentive.secondsClaimed += _secondsInsideX128;
    incentive.rewardsUnclaimed -= _rewards;

    rewards[_deposit.ownerOf] += _rewards;

    Stake storage stake_ = stakes[_tokenId][activeIncent];
    delete stake_.secondsPerLiquidity;
    delete stake_.liquidity;

    emit UnStakedNFT(_tokenId, activeIncent);
  }

  function claim(uint256 _requestedAmount, address _to) external returns (uint256 _payOut) {
    return _claim(msg.sender, _requestedAmount, _to);
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
    tokenReward.safeTransfer(_to, _payOut);

    emit RewardsClaimed(user, _payOut);
  }

  function compound(uint256 _tokenId, uint128 _minLiquidity) external {
    require(deposits[_tokenId].ownerOf == msg.sender, "!owner");

    (uint256 _amount0, uint256 _amount1) = nonfungiblePositionManager.collect(
      INonfungiblePositionManager.CollectParams({
        tokenId: _tokenId,
        recipient: address(this),
        amount0Max: type(uint128).max,
        amount1Max: type(uint128).max
      })
    );

    (uint256 _swapAmount, bool _zeroForOne) = UniswapV3Zap.calc(
      UniswapV3Zap.CalcParams(
        poolIncent,
        _amount0,
        _amount1,
        deposits[_tokenId].tickLower,
        deposits[_tokenId].tickUpper
      )
    );

    address _tokenIn = _zeroForOne ? address(token0) : address(token1);
    address _tokenOut = _zeroForOne ? address(token1) : address(token0);

    uint256 _amountOut = swapRouter.exactInputSingle(
      IUniswapSwapRouter02.ExactInputSingleParams({
        tokenIn: _tokenIn,
        tokenOut: _tokenOut,
        fee: poolIncent.fee(),
        recipient: address(this),
        amountIn: _swapAmount,
        amountOutMinimum: 0,
        sqrtPriceLimitX96: 0
      })
    );

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
      token0.safeTransfer(deposits[_tokenId].ownerOf, _amount0 - _actualAmount0);
    }
    if (_amount1 > _actualAmount1) {
      token1.safeTransfer(deposits[_tokenId].ownerOf, _amount1 - _actualAmount1);
    }
  }

  function withdraw(uint256 _tokenId, uint256 _index, address _to) external {
    require(_to != address(0), "bad _to");
    Deposit memory _deposit = deposits[_tokenId];
    require(_deposit.ownerOf == msg.sender, "!owner");
    require(_deposit.isStaked == false, "staked");
    require(tokenIds[_index] == _tokenId, "bad index");

    delete deposits[_tokenId];
    tokenIds[_index] = tokenIds[tokenIds.length - 1];
    delete tokenPosition[_tokenId];
    tokenIds.pop();

    nonfungiblePositionManager.safeTransferFrom(address(this), _to, _tokenId);

    emit NFTWithdrawn(msg.sender, _tokenId, _to);
  }

  function onERC721Received(
    address,
    address _from,
    uint256 _tokenId,
    bytes calldata
  ) external returns (bytes4) {
    require(msg.sender == address(nonfungiblePositionManager), "caller !UniV3NFT");
    require(tokenIds.length < maxPos, "full");

    (, , , , , int24 _tickLower, int24 _tickUpper, , , , , ) = nonfungiblePositionManager.positions(
      _tokenId
    );

    deposits[_tokenId] = Deposit({
      ownerOf: _from,
      isStaked: false,
      tickLower: _tickLower,
      tickUpper: _tickUpper
    });

    tokenPosition[_tokenId] = tokenIds.length;
    tokenIds.push(_tokenId);
    
    _stake(activeIncent, _tokenId);

    emit NFTDeposited(_tokenId, _from);

    return this.onERC721Received.selector;
  }

}
