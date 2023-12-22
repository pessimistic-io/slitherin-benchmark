// SPDX-License-Identifier: Business Source License 1.1
pragma solidity 0.8.18;

import {Ownable} from "./Ownable.sol";
import {BaseUpgradeableModule} from "./BaseUpgradeableModule.sol";

contract ModuleRegistry is Ownable {
    mapping(bytes32 => address) private registryMap;

    function registerModule(bytes32 id, address addr) external onlyOwner {
        require(id != bytes4(0x0), "INVALID_MODULE_ID");
        require(addr != address(0x0), "INVALID_MODULE_ADDRESS");
        require(registryMap[id] == address(0x0), "MODULE_ALREADY_REGISTERED");
        registryMap[id] = addr;
    }

    function getModuleAddress(bytes32 id) external view returns (address) {
        return registryMap[id];
    }

    function getModuleVersion(bytes32 id) external view returns (uint8) {
        return BaseUpgradeableModule(registryMap[id]).getVersion();
    }
}

