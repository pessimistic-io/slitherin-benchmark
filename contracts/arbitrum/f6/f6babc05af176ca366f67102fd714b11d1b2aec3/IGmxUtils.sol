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
  function getPositionInfo(
    address dataStore,
    IReader reader,
    address market,
    address referralStorage,
    bytes32 key,
    IManager manager
  ) external view returns (PositionData memory);
  function getPositionSizeInUsd(address dataStore, bytes32 key) external view returns (uint256 sizeInUsd);
  function getExecutionGasLimit(address dataStore, Order.OrderType orderType, uint256 callbackGasLimit) external view returns (uint256 executionGasLimit);
  function tokenToUsdMin(address manager, address token, uint256 balance) external view returns (uint256);
  function setPerpVault(address perpVault) external;
}

