// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

/// @title IGMXV2OrchestratorReader
/// @dev Interface for GMXV2OrchestratorReader contract
interface IGMXV2OrchestratorReader {
    function gmxDataStore() external view returns (address);
}
