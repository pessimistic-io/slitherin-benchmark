// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.12;

import { OwnableUpgradeable } from "./OwnableUpgradeable.sol";
import { AccessControlUpgradeable } from "./AccessControlUpgradeable.sol";

import { Beacon } from "./Beacon.sol";

/**
 * @dev contract managing beacon data for all vaults
 */
abstract contract BeaconManager is
    OwnableUpgradeable,
    AccessControlUpgradeable
{
    /// @dev Beacon registeration event
    /// @param _name The name of the beacon getting registered
    /// @param _address The implementation address that this beacon will point to
    /// @param _ipfsHash IPFS hash for the config of this beacon
    event BeaconRegistered(string _name, address _address, string _ipfsHash);

    /// @dev Beacon config updation event
    /// @param _name The name of the beacon getting registered
    /// @param _ipfsHash updated IPFS hash for the config of this beacon
    event BeaconConfigUpdated(string _name, string _ipfsHash);

    /// @dev Beacon deregisteration event
    /// @param _name The name of the beacon getting registered
    event BeaconDeregistered(string _name);

    // Beacon creator, used to create and register new beacons for new vault types
    bytes32 internal constant BEACON_CREATOR = keccak256("BEACON_CREATOR");

    // Mapping beaconName => beacon address. Used to find the beacon for a given vault type.
    mapping(string => address) public beaconAddresses;

    // Mapping address => beaconName. Used to find what vault type a given beacon or vault is.
    // Note that beaconTypes applies to both beacons and vaults.
    mapping(address => string) public beaconTypes;

    /// @dev Registers a beacon associated with a new vault type
    /// @param _name The name of the vault type this beacon will be using
    /// @param _address The address of the beacon contract
    /// @param _ipfsConfigForBeacon IPFS hash for the config of this beacon
    /// @dev This function is only available to the beacon creator
    /// @dev Registers any address as a new beacon. Useful for alternative beacon types (i.e. a contract which will use a proxy structure other than the standard beacon).
    function registerBeacon(
        string calldata _name,
        address _address,
        string memory _ipfsConfigForBeacon
    ) public onlyRole(BEACON_CREATOR) {
        // Ensure no beacon exists with given name, so that this function can't edit an existing beacon address
        require(beaconAddresses[_name] == address(0), "Beacon already exists");

        // Register beacon
        beaconAddresses[_name] = _address;
        beaconTypes[_address] = _name;
        emit BeaconRegistered(_name, _address, _ipfsConfigForBeacon);
    }

    /// @dev Deploy new beacon for a new vault type AND register it
    /// @param _address The address of the implementation for the beacon
    /// @param _name The name of the beacon (identifier)
    /// @param _ipfsConfigForBeacon IPFS hash for the config of this beacon
    /// note that the contract registered as a beacon should not be used as a vault, to avoid confusion.
    function deployAndRegisterBeacon(
        address _address,
        string calldata _name,
        string calldata _ipfsConfigForBeacon
    ) external onlyRole(BEACON_CREATOR) returns (address) {
        // Ensure no beacon exists with given name, so that this function can't edit an existing beacon address
        require(beaconAddresses[_name] == address(0), "Beacon already exists");

        // Deploy new beacon instance
        Beacon newBeacon = new Beacon(_address);

        // Transfer ownership to governance
        newBeacon.transferOwnership(owner());

        // Record beacon address at beacon name, so that new vaults can be created with this beacon by passing in beacon name
        beaconAddresses[_name] = address(newBeacon);
        beaconTypes[address(newBeacon)] = _name;

        emit BeaconRegistered(_name, _address, _ipfsConfigForBeacon);
        return address(newBeacon);
    }

    /// @dev Updates the ipfs link storing the beaconConfig
    /// @param _name The name of the beacon (identifier)
    /// @param _newIPFSConfigForBeacon IPFS hash for the config of this beacon
    function updateBeaconConfig(
        string calldata _name,
        string calldata _newIPFSConfigForBeacon
    ) external onlyRole(BEACON_CREATOR) {
        require(beaconAddresses[_name] != address(0), "Beacon does not exist");
        emit BeaconConfigUpdated(_name, _newIPFSConfigForBeacon);
    }

    /// @dev Removes a beacon associated with a vault type
    /// @param _name The name of the beacon (identifier)
    /// @dev This will stop the creation of more vaults of the type provided
    function deregisterBeacon(string calldata _name)
        external
        onlyRole(BEACON_CREATOR)
    {
        emit BeaconDeregistered(_name);
        delete beaconAddresses[_name];
    }
}

