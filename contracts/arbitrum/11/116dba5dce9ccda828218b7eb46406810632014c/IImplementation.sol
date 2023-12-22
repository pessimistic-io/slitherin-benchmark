// SPDX-License-Identifier: BSL-1.1

pragma solidity 0.8.12;

interface IImplementation {
    /// @dev To initialize a vault.
    function initialize(
        address _vaultManager,
        address _orchestrator,
        address _steer,
        bytes calldata _params
    ) external;
}

