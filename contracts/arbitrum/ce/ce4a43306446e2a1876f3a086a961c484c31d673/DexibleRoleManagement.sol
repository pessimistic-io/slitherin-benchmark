//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.17;

import "./LibStorage.sol";
import "./LibRoleManagement.sol";
import "./LibConstants.sol";

import "./console.sol";

/**
 * Role management base contract that manages certain key roles for Dexible contract.
 */
abstract contract DexibleRoleManagement {

    //emitted when role is added
    event RoleSet(address indexed member, string role);

    //emitted when role revoked
    event RoleRevoked(address indexed member, string role);

    using LibRoleManagement for LibRoleManagement.RoleStorage;

    modifier onlyRelay() {
        require(LibStorage.getRoleStorage().hasRole(msg.sender, LibConstants.RELAY), "Unauthorized relay");
        _;
    }

    modifier onlyCreator() {
        require(LibStorage.getRoleStorage().creator == msg.sender, "Unauthorized");
        _;
    }

    modifier onlyRoleManager() {
        require(hasRole(msg.sender, LibConstants.ROLE_MGR), "Unauthorized");
        _;
    }

    function addRelay(address relay) public {
        setRole(relay, LibConstants.RELAY);
    }

    function addRelays(address[] calldata relays) public {
        for(uint i=0;i<relays.length;++i) {
            setRole(relays[i], LibConstants.RELAY);
        }
    }

    function removeRelay(address relay) public {
        removeRole(relay, LibConstants.RELAY);
    }

    function isRelay(address relay) public view returns(bool) {
        return hasRole(relay, LibConstants.RELAY);
    }

    function setRole(address member, string memory role) public onlyRoleManager {
         LibStorage.getRoleStorage().setRole(member, role);
    }

    function setRoles(address member, string[] calldata roles) public onlyRoleManager {
         LibStorage.getRoleStorage().setRoles(member, roles);
    }

    function removeRole(address member, string memory role) public onlyRoleManager {
         LibStorage.getRoleStorage().removeRole(member, role);
    }

    function removeRoles(address member, string[] calldata roles) public onlyRoleManager {
         LibStorage.getRoleStorage().removeRoles(member, roles);
    }

    function hasRole(address member, string memory role) public view returns (bool) {
        return  LibStorage.getRoleStorage().hasRole(member, role);
    }
}
