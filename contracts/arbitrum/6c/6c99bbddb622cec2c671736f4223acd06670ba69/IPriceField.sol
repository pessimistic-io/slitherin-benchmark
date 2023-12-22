// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.12;

interface IPriceField {
    event UpdateFloorPrice(uint256 newFloorPrice);

    function setFloorPrice(uint256 floorPrice_) external;

    function increaseSupplyWithNoPriceImpact(uint256 amount) external;

    function exerciseAmount() external view returns (uint256);

    function slope() external view returns (uint256);

    function slope0() external view returns (uint256);

    function floorPrice() external view returns (uint256);

    function x1(uint256 targetFloorPrice) external view returns (uint256);

    function x1() external view returns (uint256);

    function x2() external view returns (uint256);

    function c() external view returns (uint256);

    function c1() external view returns (uint256);

    function b2() external view returns (uint256);

    function k() external view returns (uint256);

    function finalPrice1(uint256 x, bool round) external view returns (uint256);

    function finalPrice2(uint256 x, bool round) external view returns (uint256);

    function getPrice1(
        uint256 xs,
        uint256 xe,
        bool round
    ) external view returns (uint256);

    function getPrice2(
        uint256 xs,
        uint256 xe,
        bool round
    ) external view returns (uint256);

    function getUseFPBuyPrice(
        uint256 amount
    ) external view returns (uint256 toLiquidityPrice, uint256 fees);

    function getBuyPrice(
        uint256 amount
    ) external view returns (uint256 toLiquidityPrice, uint256 fees);

    function getSellPrice(
        uint256 xe,
        uint256 amount
    ) external view returns (uint256 toUserPrice, uint256 fees);

    function getSellPrice(
        uint256 amount
    ) external view returns (uint256 toUserPrice, uint256 fees);
}

