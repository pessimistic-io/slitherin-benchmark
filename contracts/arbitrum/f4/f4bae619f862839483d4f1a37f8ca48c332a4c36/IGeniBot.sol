// SPDX-License-Identifier: MIT

pragma solidity 0.8.11;

interface IGeniBot {
    function initialize(
        address _tokenPlay,
        address _positionRouter,
        address _vault,
        address _router,
        address _botFactory,
        address _userAddress,
        uint256 _fixedMargin,
        uint256 _positionLimit,
        uint256 _takeProfit,
        uint256 _stopLoss
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
}

