// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Context.sol";

abstract contract Ownable is Context {
  bool private _setup;
  address private _owner;

  event OwnershipTransferred(
    address indexed previousOwner,
    address indexed newOwner
  );

  function _setupOwner(address theOwner) internal virtual {
    require(!_setup, "Ownable: setup already");

    _setup = true;
    _owner = theOwner;
    emit OwnershipTransferred(address(0), theOwner);
  }

  /**
   * @dev Returns the address of the current owner.
   */
  function owner() public view returns (address) {
    return _owner;
  }

  /**
   * @dev Throws if called by any account other than the owner.
   */
  modifier onlyOwner() {
    require(owner() == _msgSender(), "Ownable: caller is not the owner");
    _;
  }
}

