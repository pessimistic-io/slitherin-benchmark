// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "./CREATE3.sol";

contract Create3Factory {
    constructor() {}

    function deploy(bytes32 salt, bytes memory bytecode, uint256 value) public returns (address) {
        return CREATE3.deploy(salt, bytecode, value);
    }

    function getDeployed(bytes32 salt) public view returns (address) {
        return CREATE3.getDeployed(salt);
    }
}

