// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IController {
    function tickSpreadUpper(
        address strategyAddress
    ) external view returns (int24);

    function tickSpreadLower(
        address strategyAddress
    ) external view returns (int24);

    function tickGapUpper(
        address strategyAddress
    ) external view returns (int24);

    function tickGapLower(
        address strategyAddress
    ) external view returns (int24);

    function tickBoundaryOffset(
        address strategyAddress
    ) external view returns (int24);

    function rescaleTickBoundaryOffset(
        address strategyAddress
    ) external view returns (int24);

    function lastRescaleTick(
        address strategyAddress
    ) external view returns (int24);
}

