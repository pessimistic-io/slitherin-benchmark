// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

interface IGmxPositionManager {
    function executeDecreaseOrder(
        address _address,
        uint256 _orderIndex,
        address payable _feeReceiver
    ) external;

    function executeIncreaseOrder(
        address _address,
        uint256 _orderIndex,
        address payable _feeReceiver
    ) external;

    function maxGlobalLongSizes(address _token) external view returns (uint256);

    function maxGlobalShortSizes(
        address _token
    ) external view returns (uint256);
}

