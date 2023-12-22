// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

abstract contract Ownable {
    address private _owner;

    event OwnershipTransferred(address, address);

    constructor(address ownerAddr) {
        _owner = ownerAddr;
    }

    function owner() public view virtual returns (address) {
        return _owner;
    }

    modifier onlyOwner() {
        require(owner() == msg.sender, 'Caller is not the owner.');
        _;
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        if (_owner != newOwner) {
            emit OwnershipTransferred(_owner, newOwner);
            _owner = newOwner;
        }
    }
}

