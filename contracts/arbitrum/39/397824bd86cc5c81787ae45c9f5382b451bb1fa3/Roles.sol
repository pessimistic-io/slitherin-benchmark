//SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

//A repo of all roles for use in Smols on Chain

contract Roles {
    bytes32 internal constant OWNER_ROLE = keccak256("OWNER");
    //GRANTING ADMIN IS SIMILAR TO GRANTING OWNER, USE WITH CAUTION.
    bytes32 internal constant ADMIN_ROLE = keccak256("ADMIN");
    bytes32 internal constant ROLE_GRANTER_ROLE = keccak256("ROLE_GRANTER");

    bytes32 internal constant SCHOOL_ADMIN_ROLE = keccak256("SCHOOL_ADMIN");
    bytes32 internal constant SCHOOL_ALLOWED_ADJUSTER_ROLE = keccak256("SCHOOL_ALLOWED_ADJUSTER");
    
    bytes32 internal constant SMOLS_PRIVILIGED_MINTER_ROLE = keccak256("SMOLS_PRIVILIGED_MINTER");

    bytes32 internal constant SMOLS_ADDRESS_REGISTRY_ADMIN_ROLE =  keccak256("SMOLS_ADDRESS_REGISTRY_ADMIN");

    bytes32 internal constant SMOLS_EXCHANGER_ADMIN_ROLE = keccak256("SMOLS_EXCHANGER_ADMIN");

    bytes32 internal constant SMOLS_RENDERER_ADMIN_ROLE = keccak256("SMOLS_RENDERER_ADMIN");

    bytes32 internal constant SMOLS_STATE_SETTER_ROLE = keccak256("SMOLS_STATE_SETTER");
    bytes32 internal constant SMOLS_STATE_EXCHANGER_ROLE = keccak256("SMOLS_STATE_EXCHANGER");

    bytes32 internal constant SMOLS_TRAIT_STORAGE_ADMIN_ROLE = keccak256("SMOLS_TRAIT_STORAGE_ADMIN");
}
