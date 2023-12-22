// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.15;

/**
 * @title  IDiagonalRegistryProxy contract interface
 * @author Diagonal Finance
 */
interface IDiagonalRegistryProxy {
    /**
     * @dev Proxy initializer function. Necessary because we do not use constructors,
     * because of easier handling of deterministic deployments (create2).
     */
    function initializeProxy(address implementation, bytes memory data) external;
}

