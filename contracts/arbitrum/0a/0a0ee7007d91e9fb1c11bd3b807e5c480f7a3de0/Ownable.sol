// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "./Context.sol";
import "./Errors.sol";

abstract contract Ownable is Context {
    address private _owner;

    constructor(address owner_) {
        if (owner_ == address(0)) revert ZeroAddress();
        _owner = owner_;
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        if (msg.sender != _owner) revert Restricted();
        _;
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view virtual returns (address) {
        return _owner;
    }
}

