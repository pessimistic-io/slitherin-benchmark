// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./IERC20.sol";
import "./IDegenPriceManager.sol";
import "./IDegenPoolManager.sol";
import "./IDegenMain.sol";

interface IDegenRouter {
  function degenMain() external view returns (IDegenMain);

  function priceFreshnessThreshold() external view returns (uint256);

  function priceManager() external view returns (IDegenPriceManager);

  function poolManager() external view returns (IDegenPoolManager);

  function submitOrderManual(
    uint16 _positionLeverage,
    uint96 _wagerAmount,
    uint96 _minOpenPrice,
    uint96 _maxOpenPrice,
    uint32 _timestampExpired,
    address _marginAsset,
    bool _isLong
  ) external returns (uint256 orderIndex_);

  function liquidateLiquidatablePositionsOnChainPrice()
    external
    returns (uint256 amountOfLiquidations_);

  function liquidateLiquidatablePositions(
    bytes calldata _updateData
  ) external returns (uint256 amountOfLiquidations_);

  function cancelOpenOrder(uint256 _orderIndex) external returns (uint256 marginAmount_);

  function executeOpenOrder(
    bytes calldata _updateData,
    uint256 _orderIndex
  ) external returns (bytes32 positionKey_, uint256 executionPrice_, bool _successFull);

  function closeOpenPosition(
    bytes calldata _updateData,
    bytes32 _positionKey
  ) external returns (uint256 executionPrice_, bool _successFull);

  function liquidatePosition(
    bytes calldata _updateData,
    bytes32 _positionKey
  ) external returns (uint256 executionPrice_, bool _successFull);

  event OpenOrderCancelled(
    uint256 indexed orderIndex,
    address indexed player,
    uint256 marginAmount
  );

  event PositionLiquidationFailed(
    bytes32 indexed positionKey,
    address indexed liquidator,
    uint256 executionPrice_
  );

  event PositionCloseFail(
    bytes32 indexed positionKey,
    address indexed player,
    uint256 executionPrice
  );

  event OpenOrderExecuted(
    bytes32 indexed positionKey,
    address indexed player,
    uint256 executionPrice,
    uint256 stableCoinMargin,
    uint256 swapFeePaidStableCoin
  );

  event PositionClosed(bytes32 indexed positionKey, address indexed player, uint256 executionPrice);

  event OpenOrderNotExecuted(
    bytes32 indexed positionKey,
    address indexed player,
    uint256 executionPrice
  );

  event PositionLiquidated(
    bytes32 indexed positionKey,
    address indexed liquidator,
    uint256 executionPrice
  );

  event OpenOrderSubmitted(uint256 orderIndex, address indexed player, uint256 marginAmount);

  event AllowedWagerSet(address asset, bool allowed);

  event FailedOnExecutionSet(bool failedOnExecution);

  event PriceFreshnessThresholdSet(uint256 priceFreshnessThreshold);
  
  event AllowedKeeperSet(address _keeper, bool _allowed);

  event ControllerChanged(address _newController);
}

