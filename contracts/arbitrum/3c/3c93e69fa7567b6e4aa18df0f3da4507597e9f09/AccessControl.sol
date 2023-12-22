// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./IAccessControl.sol";
import "./Context.sol";
import "./Strings.sol";
import "./ERC165.sol";
import "./EnumerableSet.sol";
import "./Admin.sol";

/**
 * @dev This is a modified version of @openzeppelin's AccessControl, giving all control to Admin
 * address and have the ability to clear all current role accounts. Contract module that allows
 * children to implement role-based access control mechanisms. This is a lightweight version that
 * doesn't allow enumerating role members except through off-chain means by accessing the contract
 * event logs.
 *
 * Roles are referred to by their `bytes32` identifier. These should be exposed
 * in the external API and be unique. The best way to achieve this is by
 * using `public constant` hash digests:
 *
 * ```
 * bytes32 public constant MY_ROLE = keccak256("MY_ROLE");
 * ```
 *
 * Roles can be used to represent a set of permissions. To restrict access to a
 * function call, use {hasRole}:
 *
 * ```
 * function foo() public {
 *     require(hasRole(MY_ROLE, msg.sender));
 *     ...
 * }
 * ```
 *
 * Roles can be granted and revoked dynamically via the {grantRole} and
 * {revokeRole} functions. Each role is associated with admin role, and only
 * accounts that have a role's admin role can call {grantRole} and {revokeRole}.
 */
abstract contract AccessControl is Context, IAccessControl, ERC165, Admin {
  using EnumerableSet for EnumerableSet.AddressSet;

  bytes32 public constant FREEZE = keccak256('FREEZE');
  bytes32 public constant TRANSFER = keccak256('TRANSFER');

  struct RoleData {
    mapping(address => bool) members;
  }

  mapping(bytes32 => RoleData) private roles;

  mapping(bytes32 => EnumerableSet.AddressSet) private members;

  constructor(address _admin) Admin(_admin) {}

  /**
   * @dev Modifier that checks that an account has a specific _role. Reverts
   * with a standardized message including the required _role.
   *
   * The format of the revert reason is given by the following regular expression:
   *
   *  /^AccessControl: account (0x[0-9a-f]{40}) is missing _role (0x[0-9a-f]{64})$/
   *
   * _Available since v4.1._
   */
  modifier onlyRole(bytes32 _role) {
    _checkRole(_role);
    _;
  }

  /**
   * @dev See {IERC165-supportsInterface}.
   */
  function supportsInterface(bytes4 _interfaceId)
    public
    view
    virtual
    override
    returns (bool)
  {
    return
      _interfaceId == type(IAccessControl).interfaceId ||
      super.supportsInterface(_interfaceId);
  }

  /**
   * @dev Returns `true` if `_account` has been granted `_role`.
   */
  function hasRole(bytes32 _role, address _account)
    public
    view
    virtual
    override
    returns (bool)
  {
    return roles[_role].members[_account];
  }

  /**
   * @dev Revert with a standard message if `_msgSender()` is missing `_role`.
   * Overriding this function changes the behavior of the {onlyRole} modifier.
   *
   * Format of the revert message is described in {_checkRole}.
   *
   * _Available since v4.6._
   */
  function _checkRole(bytes32 _role) internal view virtual {
    _checkRole(_role, _msgSender());
  }

  /**
   * @dev Revert with a standard message if `_account` is missing `_role`.
   *
   * The format of the revert reason is given by the following regular expression:
   *
   *  /^AccessControl: account (0x[0-9a-f]{40}) is missing role (0x[0-9a-f]{64})$/
   */
  function _checkRole(bytes32 _role, address _account) internal view virtual {
    if (!hasRole(_role, _account)) {
      revert(
        string(
          abi.encodePacked(
            'AccessControl: account ',
            Strings.toHexString(_account),
            ' is missing role ',
            Strings.toHexString(uint256(_role), 32)
          )
        )
      );
    }
  }

  /**
   * @dev Revokes `_role` from the calling account.
   *
   * Roles are often managed via {grantRole} and {revokeRole}: this function's
   * purpose is to provide a mechanism for accounts to lose their privileges
   * if they are compromised (such as when a trusted device is misplaced).
   *
   * If the calling account had been revoked `_role`, emits a {RoleRevoked}
   * event.
   *
   * Requirements:
   *
   * - the caller must be `account`.
   *
   * May emit a {RoleRevoked} event.
   */
  function renounceRole(bytes32 _role, address _account)
    public
    virtual
    override
  {
    require(
      _account == _msgSender(),
      'AccessControl: can only renounce roles for self'
    );

    _revokeRole(_role, _account);
  }

  /**
   * @dev Grants `_role` to `_account`.
   *
   * Internal function without access restriction.
   *
   * May emit a {RoleGranted} event.
   */
  function _grantRole(bytes32 _role, address _account) internal virtual {
    if (!hasRole(_role, _account)) {
      roles[_role].members[_account] = true;
      members[_role].add(_account);
      emit RoleGranted(_role, _account, _msgSender());
    }
  }

  /**
   * @dev Revokes `_role` from `_account`.
   *
   * Internal function without access restriction.
   *
   * May emit a {RoleRevoked} event.
   */
  function _revokeRole(bytes32 _role, address _account) internal virtual {
    if (hasRole(_role, _account)) {
      roles[_role].members[_account] = false;
      members[_role].remove(_account);
      emit RoleRevoked(_role, _account, _msgSender());
    }
  }

  /**
   * @dev Grants TRANSFER role to `_account`.
   *
   * If `account` had not been already granted TRANSFER ROLE, emits a {RoleGranted}
   * event.
   *
   * May emit a {RoleGranted} event.
   */
  function grantTransferRole(address _account) external virtual onlyAdmin {
    _grantRole(TRANSFER, _account);
  }

  /**
   * @dev Revoke TRANSFER role to `_account`.
   *
   * If `account` had not been already granted TRANSFER ROLE, emits a {RoleRevoked}
   * event.
   *
   * May emit a {RoleRevoked} event.
   */
  function revokeTransferRole(address _account) external virtual onlyAdmin {
    _revokeTransferRole(_account);
  }

  function _revokeTransferRole(address _account) private {
    _revokeRole(TRANSFER, _account);
  }

  /**
   * @dev Revokes TRANSFER role to everyone who has.
   */
  function clearTransferAccounts() external virtual onlyAdmin {
    uint256 length = members[TRANSFER].length();

    for (uint256 i = length; i > 0; i--) {
      _revokeTransferRole(members[TRANSFER].at(i - 1));
    }
  }

  /**
   * @dev Grants FREEZE role to `_account`.
   *
   * If `account` had not been already granted FREEZE ROLE, emits a {RoleGranted}
   * event.
   *
   * May emit a {RoleGranted} event.
   */
  function grantFreezeRole(address _account) external virtual onlyAdmin {
    _grantRole(FREEZE, _account);
  }

  /**
   * @dev Revoke FREEZE role to `_account`.
   *
   * If `account` had not been already granted FREEZE ROLE, emits a {RoleRevoked}
   * event.
   *
   * May emit a {RoleRevoked} event.
   */
  function revokeFreezeRole(address _account) external virtual onlyAdmin {
    _revokeFreezeRole(_account);
  }

  function _revokeFreezeRole(address _account) private {
    _revokeRole(FREEZE, _account);
  }

  /**
   * @dev Revokes FREEZE role to everyone who has.
   */
  function clearFreezeAccounts() external virtual onlyAdmin {
    uint256 length = members[FREEZE].length();

    for (uint256 i = length; i > 0; i--) {
      _revokeFreezeRole(members[FREEZE].at(i - 1));
    }
  }

  /**
   * @dev Get all account with role `_role`.
   */
  function getRoleAccounts(bytes32 _role) external view onlyAdmin returns (address[] memory) {
    return members[_role].values();
  }
}

