// SPDX-License-Identifier: MIT

pragma solidity 0.8.6 || 0.6.12;

interface IPositionRouter {
    function increasePositionRequestKeysStart() external returns (uint256);
    function decreasePositionRequestKeysStart() external returns (uint256);
    function executeIncreasePositions(uint256 _count, address payable _executionFeeReceiver) external;
    function executeIncreasePosition(bytes32 _key, address payable _executionFeeReceiver) external;
    function executeDecreasePositions(uint256 _count, address payable _executionFeeReceiver) external;
    function cancelIncreasePosition(bytes32 _key, address payable _executionFeeReceiver) external;
    function executeDecreasePosition(bytes32 _key, address payable _executionFeeReceiver) external;
    function cancelDecreasePosition(bytes32 _key, address payable _executionFeeReceiver) external;
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
    function createIncreasePositionETH(
        address[] memory _path,
        address _indexToken,
        uint256 _minOut,
        uint256 _sizeDelta,
        bool _isLong,
        uint256 _acceptablePrice,
        uint256 _executionFee,
        bytes32 _referralCode,
        address _callbackTarget
    ) external payable;
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
    function minExecutionFee() external view returns (uint256 minExecutionFee);
    function getRequestKey(address _account, uint256 _index) external pure returns (bytes32);
    function decreasePositionsIndex(address _account) external returns (uint256);
}

