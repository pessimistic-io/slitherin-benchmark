// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.4.1 (access/Ownable.sol)

pragma solidity ^0.8.16;

import "./utils_Context.sol";

/**
 * @dev Contract module which provides a basic access control mechanism, where
 * there is an account (an owner) that can be granted exclusive access to
 * specific functions.
 *
 * By default, the owner account will be the one that deploys the contract. This
 * can later be changed with {transferOwnership}.
 *
 * This module is used through inheritance. It will make available the modifier
 * `onlyOwner`, which can be applied to your functions to restrict their use to
 * the owner.
 */
abstract contract OwnableAdmins {
  address[] private _admins;

  event AdminAdded(address indexed newAdmin);
  event AdminRemoved(address indexed oldAdmin);

  /**
   * @dev Initializes the contract setting the deployer as the initial owner.
   */
  constructor() {
    _addAdmin(msg.sender);
  }

  modifier onlyAdmins() {
    require(isAdmin(address(msg.sender)), "Caller is not Admin");
    _;
  }

  function isAdmin(address _Admin) public view virtual returns (bool) {
    uint8 numOfAdmins=uint8(_admins.length);
    for (uint8 i = 0; i < numOfAdmins;) {
      if (_admins[i] == _Admin) return true;
      unchecked {i++;}
    }
    return false;
  }

  function removeAdmin(address oldAdmin) public virtual onlyAdmins {
    uint8 numOfAdmins=uint8(_admins.length);
    for (uint8 i = 0; i < numOfAdmins;) {
      if (_admins[i] == oldAdmin) {
        _admins[i] = _admins[numOfAdmins-1];
        _admins.pop();
        break;
      }
      unchecked {i++;}
    }
    emit AdminRemoved(oldAdmin);
  }

  function addAdmin(address newAdmin) public virtual onlyAdmins {
    uint8 numOfAdmins=uint8(_admins.length);
    for (uint8 i = 0; i < numOfAdmins; i++) {
      if (_admins[i] == newAdmin) return;
      unchecked {i++;}
    }
    _addAdmin(newAdmin);
  }

  function _addAdmin(address newAdmin) internal virtual {
    _admins.push(newAdmin);
    emit AdminAdded(newAdmin);
  }
}

