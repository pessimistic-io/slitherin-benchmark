// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.4;

interface IOrderBook {
  function createDecreaseOrder(
    address _indexToken,
    uint256 _sizeDelta,
    address _collateralToken,
    uint256 _collateralDelta,
    bool _isLong,
    uint256 _triggerPrice,
    bool _triggerAboveThreshold
  ) external payable;
  function cancelDecreaseOrder(uint256 _orderIndex) external;
  function getDecreaseOrder(address _account, uint256 _orderIndex) external view returns (
    address collateralToken,
    uint256 collateralDelta,
    address indexToken,
    uint256 sizeDelta,
    bool isLong,
    uint256 triggerPrice,
    bool triggerAboveThreshold,
    uint256 executionFee
  );
  function decreaseOrdersIndex(address _account) external view returns (uint256);
  function minExecutionFee() external view returns (uint256);
}

