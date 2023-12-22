// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.4;

import "./IReader.sol";
import "./IManager.sol";

interface IGmxUtils {
  struct PositionData {
    uint256 sizeInUsd;
    uint256 sizeInTokens;
    uint256 collateralAmount;
    uint256 netValueInCollateralToken;
    bool isLong;
  }

  struct OrderData {
    address market;
    address indexToken;
    address initialCollateralToken;
    address[] swapPath;
    bool isLong;
    uint256 sizeDeltaUsd;
    uint256 initialCollateralDeltaAmount;
    uint256 amountIn;
    uint256 callbackGasLimit;
  }

  enum OrderType {
    // @dev MarketSwap: swap token A to token B at the current market price
    // the order will be cancelled if the minOutputAmount cannot be fulfilled
    MarketSwap,
    // @dev LimitSwap: swap token A to token B if the minOutputAmount can be fulfilled
    LimitSwap,
    // @dev MarketIncrease: increase position at the current market price
    // the order will be cancelled if the position cannot be increased at the acceptablePrice
    MarketIncrease,
    // @dev LimitIncrease: increase position if the triggerPrice is reached and the acceptablePrice can be fulfilled
    LimitIncrease,
    // @dev MarketDecrease: decrease position at the current market price
    // the order will be cancelled if the position cannot be decreased at the acceptablePrice
    MarketDecrease,
    // @dev LimitDecrease: decrease position if the triggerPrice is reached and the acceptablePrice can be fulfilled
    LimitDecrease,
    // @dev StopLossDecrease: decrease position if the triggerPrice is reached and the acceptablePrice can be fulfilled
    StopLossDecrease,
    // @dev Liquidation: allows liquidation of positions if the criteria for liquidation are met
    Liquidation
  }
  function getPositionInfo(address market, bytes32 key) external view returns (PositionData memory);
  function getPositionSizeInUsd(bytes32 key) external view returns (uint256 sizeInUsd);
  function getExecutionGasLimit(OrderType orderType, uint256 callbackGasLimit) external view returns (uint256 executionGasLimit);
  function tokenToUsdMin(address token, uint256 balance) external view returns (uint256);
  function usdToTokenAmount(address token, uint256 usd) external view returns (uint256);
  function getSwapMarketData(address longToken, address shortToken) external view returns (bytes memory);
  function setEnvVars(address perpVault, address manager) external;
  function createOrder(OrderType orderType, OrderData memory orderData) external returns (bytes32);
  function createDecreaseOrder(bool beenLong, uint256 sl, uint256 tp) external;
  function withdrawEth() external returns (uint256);
}

