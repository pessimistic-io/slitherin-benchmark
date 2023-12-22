// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.12;

/**
 * Aggregated Signatures validator.
 */
interface ISockFunctionRegistry {
    function isAllowedFunction(
        address dest,
        bytes calldata func
    ) external view returns (bool);

    function isAllowedSockFunction(
        address dest,
        bytes calldata func
    ) external view returns (bool);

    function isAllowedPayableFunction(
        address dest,
        bytes calldata func
    ) external view returns (bool);

    function isAllowedPayableSockFunction(
        address dest,
        bytes calldata func
    ) external view returns (bool);
}

