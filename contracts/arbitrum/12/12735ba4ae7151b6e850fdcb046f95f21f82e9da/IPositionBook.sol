// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import "./PositionStruct.sol";

interface IPositionBook {
    function market() external view returns (address);

    function longStore() external view returns (address);

    function shortStore() external view returns (address);

    function initialize(address market) external;

    function getMarketSizes() external view returns (uint256, uint256);

    function getAccountSize(
        address account
    ) external view returns (uint256, uint256);

    function getPosition(
        address account,
        uint256 markPrice,
        bool isLong
    ) external view returns (Position.Props memory);

    function getPositions(
        address account
    ) external view returns (Position.Props[] memory);

    function getPositionKeys(
        uint256 start,
        uint256 end,
        bool isLong
    ) external view returns (address[] memory);

    function getPositionCount(bool isLong) external view returns (uint256);

    function getPNL(
        address account,
        uint256 sizeDelta,
        uint256 markPrice,
        bool isLong
    ) external view returns (int256);

    function getMarketPNL(uint256 longPrice, uint256 shortPrice) external view returns (int256);

    function increasePosition(
        address account,
        int256 collateralDelta,
        uint256 sizeDelta,
        uint256 markPrice,
        int256 fundingRate,
        bool isLong
    ) external returns (Position.Props memory result);

    function decreasePosition(
        address account,
        uint256 collateralDelta,
        uint256 sizeDelta,
        int256 fundingRate,
        bool isLong
    ) external returns (Position.Props memory result);

    function decreaseCollateralFromCancelInvalidOrder(
        address account,
        uint256 collateralDelta,
        bool isLong
    ) external returns (uint256);

    function liquidatePosition(
        address account,
        uint256 markPrice,
        bool isLong
    ) external returns (Position.Props memory result);
}

