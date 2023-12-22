//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IPositionRouter {
  function executeIncreasePositions(uint256 _count, address payable _executionFeeReceiver) external;

  function executeDecreasePositions(uint256 _count, address payable _executionFeeReceiver) external;

  function executeDecreasePosition(bytes32 key, address payable _executionFeeReceiver) external;

  function executeIncreasePosition(bytes32 key, address payable _executionFeeReceiver) external;

  // AKA open position /  add to position
  function createIncreasePosition(
    address[] memory _path,
    address _indexToken,
    uint256 _amountIn,
    uint256 _minOut,
    uint256 _sizeDelta,
    bool _isLong,
    uint256 _acceptablePrice,
    uint256 _executionFee,
    bytes32 _referralCode,
    address _callbackTarget
  ) external payable;

  // AKA close position /  remove from position
  function createDecreasePosition(
    address[] memory _path,
    address _indexToken,
    uint256 _collateralDelta,
    uint256 _sizeDelta,
    bool _isLong,
    address _receiver,
    uint256 _acceptablePrice,
    uint256 _minOut,
    uint256 _executionFee,
    bool _withdrawETH,
    address _callbackTarget
  ) external payable;

  function decreasePositionsIndex(address) external view returns (uint256);

  function increasePositionsIndex(address) external view returns (uint256);

  function getRequestKey(address, uint256) external view returns (bytes32);

  function minExecutionFee() external view returns (uint256);
}

