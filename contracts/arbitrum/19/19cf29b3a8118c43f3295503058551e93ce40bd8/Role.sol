// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;


library Role {
    
    /**
     * @dev The CONTROLLER role.
     */
    bytes32 public constant CONTROLLER = keccak256(abi.encode("CONTROLLER"));

}

