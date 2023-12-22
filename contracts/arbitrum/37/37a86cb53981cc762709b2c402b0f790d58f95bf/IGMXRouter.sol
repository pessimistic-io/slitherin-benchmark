//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

interface IGMXRouter {
    function setGov(address _gov) external;

    function addPlugin(address _plugin) external;

    function removePlugin(address _plugin) external;

    function approvePlugin(address _plugin) external;

    function denyPlugin(address _plugin) external;

    function pluginTransfer(address _token, address _account, address _receiver, uint256 _amount) external;

    function pluginIncreasePosition(
        address _account,
        address _collateralToken,
        address _indexToken,
        uint256 _sizeDelta,
        bool _isLong
    )
        external;

    function pluginDecreasePosition(
        address _account,
        address _collateralToken,
        address _indexToken,
        uint256 _collateralDelta,
        uint256 _sizeDelta,
        bool _isLong,
        address _receiver
    )
        external
        returns (uint256);

    function directPoolDeposit(address _token, uint256 _amount) external;

    function swap(address[] memory _path, uint256 _amountIn, uint256 _minOut, address _receiver) external;

    function swapETHToTokens(address[] memory _path, uint256 _minOut, address _receiver) external payable;

    function swapTokensToETH(address[] memory _path, uint256 _amountIn, uint256 _minOut, address payable _receiver)
        external;

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

    function increasePositionETH(
        address[] memory _path,
        address _indexToken,
        uint256 _minOut,
        uint256 _sizeDelta,
        bool _isLong,
        uint256 _price
    )
        external
        payable;

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

    function decreasePositionETH(
        address _collateralToken,
        address _indexToken,
        uint256 _collateralDelta,
        uint256 _sizeDelta,
        bool _isLong,
        address payable _receiver,
        uint256 _price
    )
        external;

    function decreasePositionAndSwap(
        address[] memory _path,
        address _indexToken,
        uint256 _collateralDelta,
        uint256 _sizeDelta,
        bool _isLong,
        address _receiver,
        uint256 _price,
        uint256 _minOut
    )
        external;

    function decreasePositionAndSwapETH(
        address[] memory _path,
        address _indexToken,
        uint256 _collateralDelta,
        uint256 _sizeDelta,
        bool _isLong,
        address payable _receiver,
        uint256 _price,
        uint256 _minOut
    )
        external;
}

