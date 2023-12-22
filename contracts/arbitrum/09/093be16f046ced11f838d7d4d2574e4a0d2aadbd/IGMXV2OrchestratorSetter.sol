// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

/// @title IGMXV2OrchestratorSetter
/// @dev Interface for GMXV2OrchestratorSetter contract
interface IGMXV2OrchestratorSetter {
    function storeGMXAddresses(bytes memory _data) external;
}
