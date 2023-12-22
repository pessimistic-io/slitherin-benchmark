// SPDX-License-Identifier: Business Source License 1.1
pragma solidity 0.8.18;

import {Ownable} from "./Ownable.sol";

contract TokenRegistry is Ownable {
    mapping(string => address) private registryMap;

    function registerToken(
        string memory id,
        address addr
    ) external onlyOwner {
        require(addr != address(0x0), "INVALID_TOKEN_ADDRESS");
        require(registryMap[id] == address(0x0), "TOKEN_ALREADY_REGISTERED");
        registryMap[id] = addr;
    }

    function getTokenAddress(
        string memory id
    ) external view returns (address) {
        return registryMap[id];
    }
}

