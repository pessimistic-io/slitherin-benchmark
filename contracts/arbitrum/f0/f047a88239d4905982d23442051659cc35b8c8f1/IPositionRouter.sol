// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.4;
pragma abicoder v2;

struct IncreasePositionRequest {
  address account;
  address[] path;
  address indexToken;
  uint256 amountIn;
  uint256 minOut;
  uint256 sizeDelta;
  bool isLong;
  uint256 acceptablePrice;
  uint256 executionFee;
  uint256 blockNumber;
  uint256 blockTime;
  bool hasCollateralInETH;
  address callbackTarget;
}

struct DecreasePositionRequest {
  address account;
  address[] path;
  address indexToken;
  uint256 collateralDelta;
  uint256 sizeDelta;
  bool isLong;
  address receiver;
  uint256 acceptablePrice;
  uint256 minOut;
  uint256 executionFee;
  uint256 blockNumber;
  uint256 blockTime;
  bool withdrawETH;
  address callbackTarget;
}

interface IPositionRouter { 
  function minExecutionFee() external view returns (uint256);
  function minTimeDelayPublic() external view returns (uint256);
  function maxGlobalLongSizes(address) external view returns (uint256);
  function maxGlobalShortSizes(address) external view returns (uint256);
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
  ) external payable returns (bytes32);
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
  ) external payable returns (bytes32);
  function increasePositionRequests(bytes32) external returns (IncreasePositionRequest calldata);
  function decreasePositionRequests(bytes32) external returns (DecreasePositionRequest calldata);
  function executeIncreasePosition(bytes32 _key, address payable _executionFeeReceiver) external returns (bool);
  function executeDecreasePosition(bytes32 _key, address payable _executionFeeReceiver) external returns (bool);
}

