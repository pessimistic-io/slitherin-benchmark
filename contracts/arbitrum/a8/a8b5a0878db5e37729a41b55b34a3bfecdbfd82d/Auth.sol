// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.13;




abstract contract Auth {
    address internal owner;
    mapping(address => bool) internal authorizations;
    mapping(address => bool) internal admins;

    constructor(address _owner) {
        owner = _owner;
        authorizations[_owner] = true;
    }

    modifier onlyOwner() {
        require(isOwner(msg.sender), "!OWNER");
        _;
    }

    modifier onlyOwnerOrAdmin() {
        require(isOwner(msg.sender) || isAdmin(msg.sender), "!OWNER or !ADMIN");
        _;
    }

    function authorize(address adr) public onlyOwner {
        authorizations[adr] = true;
    }

    function unauthorize(address adr) public onlyOwner {
        authorizations[adr] = false;
    }

    function setAdmin(address _admin, bool _status) public onlyOwner {
        admins[_admin] = _status;
    }

    function isOwner(address account) public view returns (bool) {
        return account == owner;
    }

    function isAuthorized(address adr) public view returns (bool) {
        return authorizations[adr];
    }

    function isAdmin(address adr) public view returns (bool) {
        return admins[adr];
    }

    function transferOwnership(address payable adr) public onlyOwner {
        owner = adr;
        authorizations[adr] = true;
        emit OwnershipTransferred(adr);
    }

    event OwnershipTransferred(address owner);
}

