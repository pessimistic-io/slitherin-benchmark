// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.10;

import {AddressRegistry} from "./AddressRegistry.sol";

interface IAddressRegistry {
    function createRegistry(string calldata _protocol, address _registry) external returns (uint256);

    function getRegistry(string calldata _protocol, uint256 _version) external view returns (address);

    function getLastVersion(string calldata _protocol) external view returns (uint256);

    error EmptyRegistry();
}

