// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface IGmxPositionRouter {

    function executeIncreasePosition(bytes32 _key, address payable _executionFeeReceiver) external returns (bool);

    function executeDecreasePosition(bytes32 _key, address payable _executionFeeReceiver) external returns (bool);

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

    function minExecutionFee() external view returns (uint256);

    function setPositionKeeper(address _account, bool _isActive) external;

    function getRequestKey(address _account, uint256 _index) external pure returns (bytes32);

    function getDecreasePositionRequestPath(bytes32 _key) external view returns (address[] memory);

    function cancelIncreasePosition(bytes32 _key, address payable _executionFeeReceiver) external returns (bool);

    function cancelDecreasePosition(bytes32 _key, address payable _executionFeeReceiver) external returns (bool);

    function executeIncreasePositions(uint256 _count, address payable _executionFeeReceiver) external;

    function executeDecreasePositions(uint256 _count, address payable _executionFeeReceiver) external;

    function increasePositionRequestKeysStart() external returns (uint256);

    function decreasePositionRequestKeysStart() external returns (uint256);
}

