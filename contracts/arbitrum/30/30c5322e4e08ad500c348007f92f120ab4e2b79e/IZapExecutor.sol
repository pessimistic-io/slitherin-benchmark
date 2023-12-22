// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import {IZapDexEnum} from "./IZapDexEnum.sol";
import {IERC20} from "./ERC20_IERC20.sol";

interface IZapExecutor is IZapDexEnum {
  event SwappedWithAggregator(address srcToken, uint256 amountOut);
  event SwappedWithElastic(
    address pool, address srcToken, address dstToken, uint256 spentAmount, uint256 returnedAmount
  );
  event MintedPosition(
    uint256 posID,
    int24 tickLower,
    int24 tickUpper,
    uint128 liquidity,
    uint256 usedAmount0,
    uint256 usedAmount1
  );
  event AddLiquidityPosition(
    uint256 posID, uint128 liquidity, uint256 usedAmount0, uint256 usedAmount1
  );

  event ZapExecuted(
    uint8 indexed _dexType,
    address indexed _srcToken,
    uint256 indexed _srcAmount,
    bool _useAggregator,
    bytes _zapResults
  );
  event KSElasticZapExecuted(
    address indexed _pool, uint256 indexed _posID, address indexed _recipient, uint128 _liquidity
  );
  /// @notice Event for collecting fees, it may collect dust tokens in the contract as well
  /// @param _totalAmount the total amount has been collected
  /// @param _actualFeeAmount the actual amount to be considered as fee
  /// @param _partnerInfo info of partner, [partnerReceiver (160 bit) + partnerPercent(96bits)]
  event FeeCollected(
    address _token,
    uint256 _totalAmount,
    uint256 _actualFeeAmount,
    uint256 _partnerInfo,
    address _feeRecipient
  );

  /// @notice FeeData, including an absoluate fee amount
  /// and partnerInfo: [partnerReceiver (160 bit) + partnerPercent(96bits)]
  struct FeeData {
    uint256 feeAmount;
    uint256 partnerInfo;
  }

  /// @notice Simple data for dex aggregator, including router address and swap data
  struct AggregatorData {
    address aggregator;
    uint256 swapAmount;
    bytes aggregatorData;
  }

  /// @notice Zap Excutor general data
  /// @param dexType type of dex to be used
  /// @param srcToken token to be used at first
  /// @param srcAmount amount of token to be used
  /// @param feeInfo fee sharing and collect data, encode of FeeData
  /// @param aggregatorInfo data for aggregator if need to swap, encode of AggregatorData
  /// @param zapExecutionData bytes data for execution, depends on dex type
  struct ZapExecutorData {
    uint8 dexType;
    IERC20 srcToken;
    uint256 srcAmount;
    bytes feeInfo;
    bytes aggregatorInfo;
    bytes zapExecutionData;
  }

  /// @notice result when zapping with KS Elastic, incluing position ID and liquidity increment
  struct ZapElasticResults {
    uint256 posID;
    uint128 liquidity;
    uint256 remainAmount0;
    uint256 remainAmount1;
  }

  /// @dev pool's information
  /// @param token0 address of token0
  /// @param fee pool's fee
  /// @param token1 address of token1
  struct PoolInfo {
    address token0;
    uint24 fee;
    address token1;
  }

  /// @param posManager address of position manager
  /// @param pool elastic pool
  /// @param posId id of the position to zap, 0 means minting a new position
  /// @param recipient the address that received new position and remaining tokens
  /// @param precisions contains precisions of token0 and token1
  /// @param minZapAmounts min amount to zap into back in case remaining
  /// @param tickLower position's lower tick
  /// @param tickUpper position's upper tick
  /// @param ticksPrevious the nearest initialized ticks which is lower than or equal tickLower, tickUpper
  /// @param minLiquidity the min liquidity should be added for the position
  /// @param offchainData data passing from offchain for swap amount, if the pool's states haven't changed
  ///   should be able to use the offchain calculation instead
  struct ElasticZapParams {
    address posManager;
    address pool;
    PoolInfo poolInfo;
    uint256 posID;
    address recipient;
    uint256 precisions;
    uint256 minZapAmounts;
    int24 tickLower;
    int24 tickUpper;
    int24[2] ticksPrevious;
    uint128 minLiquidity;
    bytes offchainData;
  }

  struct ElasticZapOffchainData {
    uint128 swapAmount;
    uint160 sqrtP;
    int24 currentTick;
    int24 nearestCurrentTick;
    uint128 baseL;
    uint128 reinvestL;
    uint128 reinvestLLast;
  }

  struct ClassicZapParams {
    address pool;
    address recipient;
    address tokenOut;
  }

  /// @notice Function to execute general zap in logic
  /// @param _executorData bytes data and will be decoded into corresponding data depends on dex type
  /// @return zapResults result of the zap, depend on dex type
  function executeZapIn(bytes calldata _executorData)
    external
    payable
    returns (bytes memory zapResults);
}

