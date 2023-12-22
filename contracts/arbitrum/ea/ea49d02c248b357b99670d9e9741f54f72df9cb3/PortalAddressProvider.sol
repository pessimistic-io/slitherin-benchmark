// Copyright (C) 2022 Portals.fi

/// @author Portals.fi
/// @notice Portals registry address provider

/// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.11;
import "./Ownable.sol";

contract PortalAddressProviderV1 is Ownable {
    /// @notice Registry is inactive if the registry address is address(0)
    struct RegistryInfo {
        address addr;
        uint256 version;
        uint256 updated;
        string description;
    }

    // Array of registries
    RegistryInfo[] internal registries;

    /// @notice Emitted when a new registry is added
    /// @param registry The newly added registry
    event AddRegistry(RegistryInfo registry);

    /// @notice Emitted when a registry is removed
    /// @param registry The removed registry
    event RemoveRegistry(RegistryInfo registry);

    /// @notice Emitted when a registry is updated
    /// @param registry The updated registry
    event UpdateRegistry(RegistryInfo registry);

    constructor(address _owner) {
        transferOwnership(_owner);
    }

    /// @notice Adds a new registry
    /// @param addr The address of the new registry
    /// @param description The description of the registry
    function addRegistry(address addr, string memory description)
        external
        onlyOwner
    {
        uint256 index = registries.length;
        registries.push(RegistryInfo(addr, 1, block.timestamp, description));

        emit AddRegistry(registries[index]);
    }

    /// @notice Removes a registry
    /// @dev sets the registry (address) to address(0)
    /// @param index The index of the registry in the registries array that is being removed
    function removeRegistry(uint256 index) external onlyOwner {
        registries[index].addr = address(0);
        registries[index].updated = block.timestamp;

        emit RemoveRegistry(registries[index]);
    }

    /// @notice Updates a registry
    /// @param index The index of the registry in the registries array that is being updated
    /// @param addr The address of the updated registry
    function updateRegistry(uint256 index, address addr) external onlyOwner {
        registries[index].addr = addr;
        ++registries[index].version;
        registries[index].updated = block.timestamp;

        emit UpdateRegistry(registries[index]);
    }

    /// @notice Returns an array of all of the registry info objects
    function getAllRegistries() external view returns (RegistryInfo[] memory) {
        return registries;
    }

    /// @notice Returns the address of the main registry
    function getRegistry() external view returns (address) {
        return registries[0].addr;
    }

    /// @notice Returns the address of the registry at the index
    /// @param index The index of the registry in the registries array whose address is being returned
    function getAddress(uint256 index) external view returns (address) {
        return registries[index].addr;
    }

    /// @notice Returns the total number of registries
    function numRegistries() external view returns (uint256) {
        return registries.length;
    }
}

