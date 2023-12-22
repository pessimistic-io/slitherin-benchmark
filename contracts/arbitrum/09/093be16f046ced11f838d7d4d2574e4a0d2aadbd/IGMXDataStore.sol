// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

interface IGMXDataStore {
    function getUint(bytes32 key) external view returns (uint256);
    function getAddress(bytes32 key) external view returns (address);
    function getBytes32Count(bytes32 key) external view returns (uint256);
}
