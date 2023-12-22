// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./DegenStructs.sol";

interface IDegenReader {
  function calculateInterestPosition(
    bytes32 _positionKey,
    uint256 _timestampAt
  ) external view returns (uint256 interestAccruedUsd_);

  function netPnlOfPositionWithInterest(
    bytes32 _positionKey,
    uint256 _assetPrice,
    uint256 _timestampAt
  ) external view returns (int256 pnlUsd_);

  function netPnlOfPositionWithInterestUpdateData(
    bytes32 _positionKey,
    bytes memory _updateData,
    uint256 _timestampAt
  ) external view returns (int256 pnlUsd_);

  function isPositionLiquidatableByKeyAtTimeUpdateData(
    bytes32 _positionKey,
    bytes memory _updateData,
    uint256 _timestampAt
  ) external view returns (bool isPositionLiquidatable_);

  function getFundingRate(bool _long) external view returns (uint256 fundingRate_);

  function getAmountOfLiquidatablePositionsUpdateData(
    bytes memory _updateData,
    uint256 _timestampAt
  ) external view returns (uint256 amountOfLiquidatablePositions_);

  function getAmountOfLiquidatablePoisitions(
    uint256 _assetPrice,
    uint256 _timestampAt
  ) external view returns (uint256 amountOfLiquidatablePositions_);

  function isPositionLiquidatable(
    bytes32 _positionKey
  ) external view returns (bool isPositionLiquidatable_);

  function isPositionLiquidatableUpdateData(
    bytes32 _positionKey,
    bytes memory _updateData
  ) external view returns (bool isPositionLiquidatable_);

  function returnOrderInfo(uint256 _orderIndex) external view returns (OrderInfo memory orderInfo_);

  function returnOpenPositionInfo(
    bytes32 _positionKey
  ) external view returns (PositionInfo memory positionInfo_);

  function returnClosedPositionInfo(
    bytes32 _positionKey
  ) external view returns (ClosedPositionInfo memory closedPositionInfo_);

  function amountOpenOrders() external view returns (uint256 openOrdersCount_);

  function amountOpenPositions() external view returns (uint256 openPositionsCount_);

  function isOpenPosition(bytes32 _positionKey) external view returns (bool isPositionOpen_);

  function isOpenOrder(uint256 _orderIndex) external view returns (bool isOpenOrder_);

  function isClosedPosition(bytes32 _positionKey) external view returns (bool isClosedPosition_);

  function getOpenPositionsInfo() external view returns (PositionInfo[] memory _positions);

  function getOpenPositionKeys() external view returns (bytes32[] memory _positionKeys);

  function getAllOpenOrdersInfo() external view returns (OrderInfo[] memory _orders);

  function getAllOpenOrderIndexes() external view returns (uint256[] memory _orderIndexes);

  function returnAllClosedPositionsOfUser(
    address _user
  ) external view returns (ClosedPositionInfo[] memory _userPositions);

  function returnAllOpenOrdersOfUser(
    address _user
  ) external view returns (OrderInfo[] memory _userOrders);

  function returnAllOpenPositionsOfUser(
    address _user
  ) external view returns (PositionInfo[] memory _userPositions);

  function getAllLiquidatablePositions(
    uint256 _assetPrice,
    uint256 _timestampAt
  ) external view returns (bytes32[] memory _liquidatablePositions);

  function getAllLiquidatablePositionsUpdateData(
    bytes memory _updateData,
    uint256 _timestampAt
  ) external view returns (bytes32[] memory _liquidatablePositions);

  function isPriceUpdateRequired() external view returns (bool isUpdateNeeded_);

  function willUpdateDataUpdateThePrice(
    bytes calldata _updateData
  ) external view returns (bool willUpdatePrice_);

  function isUpdateDataRecentEnoughForExecution(
    bytes calldata _updateData
  ) external view returns (bool isRecentEnough_);
}

