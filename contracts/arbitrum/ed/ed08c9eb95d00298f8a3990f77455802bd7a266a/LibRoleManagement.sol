//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.17;

import "./LibConstants.sol";

/**
 * Library used for role storage and update ops
 */
library LibRoleManagement {

    //emitted when role is added
    event RoleSet(address indexed member, string role);

    //emitted when role revoked
    event RoleRevoked(address indexed member, string role);

    struct RoleStorage {
        address creator;
        uint updateId;
        mapping(string => mapping(address => bool)) roles;
    }

    function initializeRoles(RoleStorage storage rs, address roleMgr) public{
        require(rs.creator == address(0), "Already initialized");
        require(roleMgr != address(0), "Invalid owner address");
        rs.creator = msg.sender;
        setRole(rs, roleMgr, LibConstants.ROLE_MGR);
        setRole(rs, msg.sender, LibConstants.ROLE_MGR);
    }

    function setRole(RoleStorage storage rs, address member, string memory role) public   {
        rs.roles[role][member] = true;
        rs.updateId++;
        emit LibRoleManagement.RoleSet(member, role);
    }

    function setRoles(RoleStorage storage rs, address member, string[] calldata roles) public  {
        for(uint i=0;i<roles.length;++i) {
            string calldata role = roles[i];
            setRole(rs, member, role);
        }
        rs.updateId++;
    }

    function removeRole(RoleStorage storage rs, address member, string memory role) public  {
        delete rs.roles[role][member];
        rs.updateId++;
        emit LibRoleManagement.RoleRevoked(member, role);
    }

    function removeRoles(RoleStorage storage rs, address member, string[] calldata roles) public  {
        for(uint i=0;i<roles.length;++i) {
            string calldata role = roles[i];
            removeRole(rs, member, role);
        }
        ++rs.updateId;
    }

    function hasRole(RoleStorage storage rs, address member, string memory role) public view returns (bool) {
        return rs.roles[role][member];
    }
}
