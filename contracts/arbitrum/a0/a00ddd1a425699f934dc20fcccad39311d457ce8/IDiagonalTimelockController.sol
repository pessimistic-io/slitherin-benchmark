// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.15;

/**
 * @title IDiagonalTimelockController contract interface
 * @author Diagonal Finance
 * @notice IDiagonalTimelockController is timelock extension, which allows to invoke
 * pause and unpause operations with admin access and without queuing.
 */
interface IDiagonalTimelockController {
    function pause(address target) external;

    function unpause(address target) external;
}

