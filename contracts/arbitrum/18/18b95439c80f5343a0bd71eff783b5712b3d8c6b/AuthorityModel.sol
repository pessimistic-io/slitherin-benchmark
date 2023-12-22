// SPDX-License-Identifier: MIT
// Metadrop Contracts (v2.0.0)

/**
 *
 * @title AuthorityModel.sol. Library for global authority components
 *
 * @author metadrop https://metadrop.com/
 *
 */

pragma solidity 0.8.19;

/**
 *
 * @dev Inheritance details:
 *      EnumerableSet           OZ enumerable mapping sets
 *      IErrors                 Interface for platform error definitions
 *
 */

import {EnumerableSet} from "./EnumerableSet.sol";
import {IErrors} from "./IErrors.sol";
import {Revert} from "./Revert.sol";

contract AuthorityModel is IErrors, Revert {
  using EnumerableSet for EnumerableSet.AddressSet;

  // Address for the factory:
  address public factory;

  // The super admin can grant and revoke roles
  address public superAdmin;

  // Enumerable set to store platform admins:
  EnumerableSet.AddressSet private _platformAdmins;

  // Enumerable set to store platform admins:
  EnumerableSet.AddressSet private _reviewAdmins;

  event SuperAdminTransferred(address oldSuperAdmin, address newSuperAdmin);
  event PlatformAdminAdded(address platformAdmin);
  event ReviewAdminAdded(address reviewAdmin);
  event PlatformAdminRevoked(address platformAdmin);
  event ReviewAdminRevoked(address reviewAdmin);

  /** ====================================================================================================================
   *                                                       MODIFIERS
   * =====================================================================================================================
   */
  /** ____________________________________________________________________________________________________________________
   *                                                                                                     -->ACCESS CONTROL
   * @dev (modifier) onlySuperAdmin. The associated action can only be taken by the super admin (an address with the
   * default admin role).
   *
   * _____________________________________________________________________________________________________________________
   */
  modifier onlySuperAdmin() {
    if (!isSuperAdmin(msg.sender)) revert CallerIsNotSuperAdmin(msg.sender);
    _;
  }

  /** ____________________________________________________________________________________________________________________
   *                                                                                                     -->ACCESS CONTROL
   * @dev (modifier) onlyPlatformAdmin. The associated action can only be taken by an address with the
   * platform admin role.
   *
   * _____________________________________________________________________________________________________________________
   */
  modifier onlyPlatformAdmin() {
    if (!isPlatformAdmin(msg.sender))
      revert CallerIsNotPlatformAdmin(msg.sender);
    _;
  }

  /** ____________________________________________________________________________________________________________________
   *                                                                                                     -->ACCESS CONTROL
   * @dev (modifier) onlyReviewAdmin. The associated action can only be taken by an address with the
   * review admin role.
   *
   * _____________________________________________________________________________________________________________________
   */
  modifier onlyReviewAdmin() {
    if (!isReviewAdmin(msg.sender)) revert CallerIsNotReviewAdmin(msg.sender);
    _;
  }

  /** ____________________________________________________________________________________________________________________
   *                                                                                                             -->GETTER
   * @dev (function) getPlatformAdmins   Getter for the enumerable list of platform admins
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @return platformAdmins_  A list of platform admins
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function getPlatformAdmins()
    public
    view
    returns (address[] memory platformAdmins_)
  {
    return (_platformAdmins.values());
  }

  /** ____________________________________________________________________________________________________________________
   *                                                                                                             -->GETTER
   * @dev (function) getReviewAdmins   Getter for the enumerable list of review admins
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @return reviewAdmins_  A list of review admins
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function getReviewAdmins()
    public
    view
    returns (address[] memory reviewAdmins_)
  {
    return (_reviewAdmins.values());
  }

  /** ____________________________________________________________________________________________________________________
   *                                                                                                             -->GETTER
   * @dev (function) isSuperAdmin   check if an address is the super admin
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @return bool
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function isSuperAdmin(address queryAddress_) public view returns (bool) {
    return (superAdmin == queryAddress_);
  }

  /** ____________________________________________________________________________________________________________________
   *                                                                                                             -->GETTER
   * @dev (function) isPlatformAdmin   check if an address is a platform admin
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @return bool
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function isPlatformAdmin(address queryAddress_) public view returns (bool) {
    return (_platformAdmins.contains(queryAddress_));
  }

  /** ____________________________________________________________________________________________________________________
   *                                                                                                             -->GETTER
   * @dev (function) isReviewAdmin   check if an address is a review admin
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @return bool
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function isReviewAdmin(address queryAddress_) public view returns (bool) {
    return (_reviewAdmins.contains(queryAddress_));
  }

  /** ____________________________________________________________________________________________________________________
   *                                                                                                     -->ACCESS CONTROL
   * @dev (function) grantPlatformAdmin  Allows the super user Default Admin to add an address to the platform admin group
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @param newPlatformAdmin_              The address of the new platform admin
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function grantPlatformAdmin(address newPlatformAdmin_) public onlySuperAdmin {
    if (newPlatformAdmin_ == address(0)) {
      _revert(PlatformAdminCannotBeAddressZero.selector);
    }
    // Add this to the enumerated list:
    _platformAdmins.add(newPlatformAdmin_);
    emit PlatformAdminAdded(newPlatformAdmin_);
  }

  /** ____________________________________________________________________________________________________________________
   *                                                                                                     -->ACCESS CONTROL
   * @dev (function) grantReviewAdmin  Allows the super user Default Admin to add an address to the review admin group.
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @param newReviewAdmin_              The address of the new review admin
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function grantReviewAdmin(address newReviewAdmin_) public onlySuperAdmin {
    if (newReviewAdmin_ == address(0)) {
      _revert(ReviewAdminCannotBeAddressZero.selector);
    }
    // Add this to the enumerated list:
    _reviewAdmins.add(newReviewAdmin_);
    emit ReviewAdminAdded(newReviewAdmin_);
  }

  /** ____________________________________________________________________________________________________________________
   *                                                                                                     -->ACCESS CONTROL
   * @dev (function) revokePlatformAdmin  Allows the super user Default Admin to revoke from the platform admin group
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @param oldPlatformAdmin_              The address of the old platform admin
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function revokePlatformAdmin(
    address oldPlatformAdmin_
  ) public onlySuperAdmin {
    // Remove this from the enumerated list:
    _platformAdmins.remove(oldPlatformAdmin_);
    emit PlatformAdminRevoked(oldPlatformAdmin_);
  }

  /** ____________________________________________________________________________________________________________________
   *                                                                                                     -->ACCESS CONTROL
   * @dev (function) revokeReviewAdmin  Allows the super user Default Admin to revoke an address to the review admin group
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @param oldReviewAdmin_              The address of the old review admin
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function revokeReviewAdmin(address oldReviewAdmin_) public onlySuperAdmin {
    // Remove this from the enumerated list:
    _reviewAdmins.remove(oldReviewAdmin_);
    emit ReviewAdminRevoked(oldReviewAdmin_);
  }

  /** ____________________________________________________________________________________________________________________
   *                                                                                                     -->ACCESS CONTROL
   * @dev (function) transferSuperAdmin  Allows the super user Default Admin to transfer this right to another address
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @param newSuperAdmin_              The address of the new default admin
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function transferSuperAdmin(address newSuperAdmin_) public onlySuperAdmin {
    address oldSuperAdmin = superAdmin;
    // Update storage of this address:
    superAdmin = newSuperAdmin_;
    emit SuperAdminTransferred(oldSuperAdmin, newSuperAdmin_);
  }
}

