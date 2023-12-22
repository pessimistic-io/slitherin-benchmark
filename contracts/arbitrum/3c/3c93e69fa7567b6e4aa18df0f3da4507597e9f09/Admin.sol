// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./Ownable.sol";

/**
 * @dev Contract module which provides a basic access control mechanism, where
 * there is an account (an credit admin) that can be granted exclusive access to
 * specific functions.
 *
 * This module is used through inheritance. It will make available the modifier
 * `onlyAdmin`, which can be applied to your functions to restrict their use to
 * the admin.
 *
 * Needs a address at deployment to set admin. Then only the owner of the contract can
 * change the admin.
 */
abstract contract Admin is Ownable {
  address private admin;

  event AdminChanged(address indexed previousAdmin, address indexed newAdmin);

  /**
   * @notice Initializes the contract setting the deployer as the initial admin.
   */
  constructor(address _admin) {
    _changeAdmin(_admin);
  }

  /**
   * @notice Returns the address of the current admin.
   */
  function getAdmin() public view virtual returns (address) {
    return admin;
  }

  /**
   * @notice Throws if called by any account other than the admin.
   */
  modifier onlyAdmin() {
    _checkAdmin();
    _;
  }

  /**
   * @notice Throws if the sender is not the admin.
   */
  function _checkAdmin() internal view virtual {
    require(admin == _msgSender(), 'Caller is not the admin');
  }

  /**
   * @notice Changes admin of the contract to a new account (`_newAdmin`).
   * Can only be called by the current owner.
   */
  function changeAdmin(address _newAdmin) public virtual onlyOwner {
    require(_newAdmin != address(0), 'New admin is the zero address');
    _changeAdmin(_newAdmin);
  }

  /**
   * @notice Changes  of the contract to a new account (`_newAdmin`).
   * Internal function without access restriction.
   */
  function _changeAdmin(address _newAdmin) internal virtual {
    address oldAdmin = admin;
    admin = _newAdmin;
    emit AdminChanged(oldAdmin, admin);
  }
}

