// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

/**
 * This is interface that allows the "plugin" mechanism of the system.
 * xToken relies on this interface for connecting different strategies/plugins/etc to the system.
 */
interface IXTokenUsage {
    function allocate(address userAddress, uint256 amount, bytes calldata data) external;

    function deallocate(address userAddress, uint256 amount, bytes calldata data) external;
}

