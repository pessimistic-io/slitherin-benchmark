// @title AddressRegistry
// @notice Provides versioned addresses of different DeFi Protocols
// @author N1mr0d <n1mr0d.tuta.io>
// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.10;

import {IAddressRegistry} from "./IAddressRegistry.sol";
import {Ownable} from "./Ownable.sol";

contract AddressRegistry is IAddressRegistry, Ownable {
    mapping(bytes32 => uint256) private version;
    mapping(bytes32 => mapping(uint256 => address)) private registry;

    event Registry(bytes32 indexed protocol, uint256 version, address registry);

    // External Functions

    /**
     * @notice Create or update a registry for a protocol
     * @dev Will revert if the caller isn't the owner
     * @param _protocol The protocol string, usually the token symbol
     * @param _registry The address that will be registered
     */
    function createRegistry(string calldata _protocol, address _registry) external onlyOwner returns (uint256) {
        bytes32 protocolHash = keccak256(abi.encodePacked(_protocol));
        uint256 newVersion = version[protocolHash] + 1;
        version[protocolHash] = newVersion;
        registry[protocolHash][newVersion] = _registry;
        emit Registry(protocolHash, newVersion, _registry);
        return newVersion;
    }

    // Getters

    /**
     * @notice Get a protocol versioned registry
     * @dev Public view
     * @param _protocol The protocol string, usually the token symbol
     * @param _version The version of the registry
     */
    function getRegistry(string calldata _protocol, uint256 _version) external view returns (address) {
        bytes32 protocolHash = keccak256(abi.encodePacked(_protocol));
        address reg = registry[protocolHash][_version];
        if (reg == address(0)) revert EmptyRegistry();
        return reg;
    }

    /**
     * @notice Get the last registry version of a protocol
     * @dev Public view
     * @param _protocol The hash of the protocol string, used as identifier
     */
    function getLastVersion(string calldata _protocol) external view returns (uint256) {
        bytes32 protocolHash = keccak256(abi.encodePacked(_protocol));
        return version[protocolHash];
    }
}

