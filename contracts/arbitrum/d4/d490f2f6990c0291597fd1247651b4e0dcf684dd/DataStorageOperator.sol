// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import "./Timestamp.sol";
import "./IAlgebraFactory.sol";
import "./IDataStorageOperator.sol";
import "./IAlgebraPoolState.sol";

import "./DataStorage.sol";
import "./AdaptiveFee.sol";

/// @title Algebra timepoints data operator
/// @notice This contract stores timepoints and calculates adaptive fee and statistical averages
contract DataStorageOperator is IDataStorageOperator, Timestamp {
  uint256 internal constant UINT16_MODULO = 65536;

  using DataStorage for DataStorage.Timepoint[UINT16_MODULO];

  DataStorage.Timepoint[UINT16_MODULO] public override timepoints;
  AlgebraFeeConfiguration public feeConfigZtO;
  AlgebraFeeConfiguration public feeConfigOtZ;

  /// @dev The role can be granted in AlgebraFactory
  bytes32 public constant FEE_CONFIG_MANAGER = keccak256('FEE_CONFIG_MANAGER');

  address private immutable pool;
  address private immutable factory;

  modifier onlyPool() {
    require(msg.sender == pool, 'only pool can call this');
    _;
  }

  constructor(address _pool) {
    (factory, pool) = (msg.sender, _pool);
  }

  /// @inheritdoc IDataStorageOperator
  function initialize(uint32 time, int24 tick) external override onlyPool {
    return timepoints.initialize(time, tick);
  }

  /// @inheritdoc IDataStorageOperator
  function changeFeeConfiguration(bool zto, AlgebraFeeConfiguration calldata _config) external override {
    require(msg.sender == factory || IAlgebraFactory(factory).hasRoleOrOwner(FEE_CONFIG_MANAGER, msg.sender));
    AdaptiveFee.validateFeeConfiguration(_config);

    if (zto) feeConfigZtO = _config;
    else feeConfigOtZ = _config;
    emit FeeConfiguration(zto, _config);
  }

  /// @inheritdoc IDataStorageOperator
  function getSingleTimepoint(
    uint32 time,
    uint32 secondsAgo,
    int24 tick,
    uint16 lastIndex
  ) external view override returns (int56 tickCumulative, uint112 volatilityCumulative) {
    DataStorage.Timepoint memory result = timepoints.getSingleTimepoint(time, secondsAgo, tick, lastIndex, timepoints.getOldestIndex(lastIndex));
    (tickCumulative, volatilityCumulative) = (result.tickCumulative, result.volatilityCumulative);
  }

  /// @inheritdoc IDataStorageOperator
  function getTimepoints(
    uint32[] memory secondsAgos
  ) external view override returns (int56[] memory tickCumulatives, uint112[] memory volatilityCumulatives) {
    (, int24 tick, , , uint16 index, , ) = IAlgebraPoolState(pool).globalState();
    return timepoints.getTimepoints(_blockTimestamp(), secondsAgos, tick, index);
  }

  /// @inheritdoc IDataStorageOperator
  function write(
    uint16 index,
    uint32 blockTimestamp,
    int24 tick
  ) external override onlyPool returns (uint16 indexUpdated, uint16 newFeeZtO, uint16 newFeeOtZ) {
    uint16 oldestIndex;
    (indexUpdated, oldestIndex) = timepoints.write(index, blockTimestamp, tick);

    if (index != indexUpdated) {
      uint88 volatilityAverage;
      bool hasCalculatedVolatility;
      AlgebraFeeConfiguration memory _feeConfig = feeConfigZtO;
      if (_feeConfig.alpha1 | _feeConfig.alpha2 == 0) {
        newFeeZtO = _feeConfig.baseFee;
      } else {
        uint88 lastVolatilityCumulative = timepoints[indexUpdated].volatilityCumulative;
        volatilityAverage = timepoints.getAverageVolatility(blockTimestamp, tick, indexUpdated, oldestIndex, lastVolatilityCumulative);
        hasCalculatedVolatility = true;
        newFeeZtO = AdaptiveFee.getFee(volatilityAverage, _feeConfig);
      }

      _feeConfig = feeConfigOtZ;
      if (_feeConfig.alpha1 | _feeConfig.alpha2 == 0) {
        newFeeOtZ = _feeConfig.baseFee;
      } else {
        if (!hasCalculatedVolatility) {
          uint88 lastVolatilityCumulative = timepoints[indexUpdated].volatilityCumulative;
          volatilityAverage = timepoints.getAverageVolatility(blockTimestamp, tick, indexUpdated, oldestIndex, lastVolatilityCumulative);
        }
        newFeeOtZ = AdaptiveFee.getFee(volatilityAverage, _feeConfig);
      }
    }
  }

  /// @inheritdoc IDataStorageOperator
  function prepayTimepointsStorageSlots(uint16 startIndex, uint16 amount) external {
    require(!timepoints[startIndex].initialized); // if not initialized, then all subsequent ones too
    require(amount > 0 && type(uint16).max - startIndex >= amount);

    unchecked {
      for (uint256 i = startIndex; i < startIndex + amount; ++i) {
        timepoints[i].blockTimestamp = 1; // will be overwritten
      }
    }
  }
}

