//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

interface IGMXPositionManager {
    function increasePosition(
        address[] memory _path,
        address _indexToken,
        uint256 _amountIn,
        uint256 _minOut,
        uint256 _sizeDelta,
        bool _isLong,
        uint256 _price
    )
        external;

    function decreasePosition(
        address _collateralToken,
        address _indexToken,
        uint256 _collateralDelta,
        uint256 _sizeDelta,
        bool _isLong,
        address _receiver,
        uint256 _price
    )
        external;

    function setPartner(address _account, bool _isActive) external;

    function setOrderKeeper(address _account, bool _isActive) external;

    function executeIncreaseOrder(address _account, uint256 _orderIndex, address payable _feeReceiver) external;

    function executeDecreaseOrder(address _account, uint256 _orderIndex, address payable _feeReceiver) external;
}

