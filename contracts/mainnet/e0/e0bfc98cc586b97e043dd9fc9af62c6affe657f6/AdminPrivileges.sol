// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

contract AdminPrivileges {
    address public _owner;

    mapping(address => bool) public admins;

    constructor() {
        _owner = msg.sender;
    }

    modifier onlyAdmins() {
        require(_owner == msg.sender || admins[msg.sender], "AdminPrivileges: caller is not an admin");
        _;
    }

    function toggleAdmin(address account) external onlyAdmins {
        if (admins[account]) {
            delete admins[account];
        } else {
            admins[account] = true;
        }
    }
}
