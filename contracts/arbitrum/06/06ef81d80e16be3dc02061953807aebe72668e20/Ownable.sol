// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.16;

import "./Context.sol";

contract Ownable is Context {
    address private _owner;
    address private _previousOwner;

    constructor() {
        address msgSender = _msgSender();
        _owner = msgSender;
        emit OwnershipTransferred(address(0), msgSender);
    }

    function owner() public view returns (address) {
        return _owner;
    }

    modifier onlyOwner() {
        require(_owner == _msgSender(), "Caller is not the owner");
        _;
    }

    function renounceOwnership() public virtual onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );

    function transferOwnership(address newOwner) public virtual onlyOwner {
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

