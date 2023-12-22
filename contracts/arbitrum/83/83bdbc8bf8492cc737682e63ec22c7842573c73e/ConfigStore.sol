// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import { Ownable } from "./Ownable.sol";
import { Multicall } from "./Multicall.sol";

interface IConfigStore {
    function changeImplementationAddress(bytes32 interfaceName, address implementationAddress) external;

    function getImplementationAddress(bytes32 interfaceName) external view returns (address);
    function getImplementationUint256(bytes32 interfaceName) external view returns (uint256);
}

error ImplementationNotFound();

contract ConfigStore is IConfigStore, Ownable, Multicall {
    mapping(bytes32 => address) public interfacesImplemented;

    event InterfaceImplementationChanged(bytes32 indexed interfaceName, address indexed newImplementationAddress);

    /**
     * @notice Updates the address of the contract that implements `interfaceName`.
     * @param interfaceName bytes32 of the interface name that is either changed or registered.
     * @param implementationAddress address of the implementation contract.
     */
    function changeImplementationAddress(
        bytes32 interfaceName,
        address implementationAddress
    )
        external
        override
        onlyOwner
    {
        interfacesImplemented[interfaceName] = implementationAddress;

        emit InterfaceImplementationChanged(interfaceName, implementationAddress);
    }

    /**
     * @notice Gets the address of the contract that implements the given `interfaceName`.
     * @param interfaceName queried interface.
     * @return implementationAddress address of the defined interface.
     */
    function getImplementationAddress(bytes32 interfaceName) external view override returns (address) {
        address implementationAddress = interfacesImplemented[interfaceName];
        if (implementationAddress == address(0x0)) revert ImplementationNotFound();
        return implementationAddress;
    }

    /**
     * @notice Gets the address of the contract that implements the given `interfaceName`.
     * @param interfaceName queried interface.
     * @return implementationUint256 uint256 of the defined interface.
     */
    function getImplementationUint256(bytes32 interfaceName) external view override returns (uint256) {
        address implementationAddress = interfacesImplemented[interfaceName];
        return uint256(uint160(implementationAddress));
    }
}

