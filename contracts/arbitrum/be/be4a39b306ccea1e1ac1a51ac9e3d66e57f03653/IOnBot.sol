// SPDX-License-Identifier: MIT

pragma solidity 0.8.11;

interface IOnBot {
    function initialize(
        address _tokenPlay,
        address _positionRouter,
        address _vault,
        address _router,
        address _botFactory,
        address _userAddress
    ) external;

    function botFactoryCollectToken() external returns (uint256);

    function getIncreasePositionRequests(uint256 _count) external returns (
        address,
        address,
        bytes32,
        address,
        uint256,
        uint256,
        bool,
        bool
    );

    function getUser() external view returns (
        address,
        uint256,
        uint256,
        uint256,
        uint256,
        uint256
    );

    function getTokenPlay() external view returns (address);
    function createIncreasePosition(
        address _trader,
        address[] memory _path,
        address _indexToken,
        uint256 _amountIn,
        uint256 _minOut,
        uint256 _sizeDelta,
        bool _isLong,
        uint256 _acceptablePrice,
        uint256 _executionFee
    ) external payable;
    function createDecreasePosition(
        address _trader,
        address[] memory _path,
        address _indexToken,
        uint256 _collateralDelta,
        uint256 _sizeDelta,
        bool _isLong,
        uint256 _acceptablePrice,
        uint256 _minOut,
        uint256 _executionFee,
        address _callbackTarget
    ) external payable;

    function updateBalanceToVault() external;
}

