// SPDX-License-Identifier: AGPL-3.0
pragma solidity =0.8.7;

import "./AccessControlEnumerable.sol";
import "./ISafeAccessControlEnumerable.sol";

contract SafeAccessControlEnumerable is
  ISafeAccessControlEnumerable,
  AccessControlEnumerable
{
  mapping(bytes32 => bytes32) private _roleToRoleAdminNominee;
  mapping(bytes32 => mapping(address => bool))
    private _roleToAccountToNominated;

  constructor() {
    _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
  }

  function setRoleAdminNominee(bytes32 role, bytes32 roleAdminNominee)
    public
    virtual
    override
    onlyRole(getRoleAdmin(role))
  {
    _setRoleAdminNominee(role, roleAdminNominee);
  }

  function acceptRoleAdmin(bytes32 role)
    public
    virtual
    override
    onlyRole(_roleToRoleAdminNominee[role])
  {
    _setRoleAdmin(role, _roleToRoleAdminNominee[role]);
    _setRoleAdminNominee(role, 0x00);
  }

  function grantRole(bytes32 role, address account)
    public
    virtual
    override
    onlyRole(getRoleAdmin(role))
  {
    _setRoleNominee(role, account, true);
  }

  function acceptRole(bytes32 role) public virtual override {
    require(
      _roleToAccountToNominated[role][_msgSender()],
      "msg.sender != role nominee"
    );
    _setRoleNominee(role, _msgSender(), false);
    _grantRole(role, _msgSender());
  }

  function revokeNomination(bytes32 role, address account)
    public
    virtual
    override
    onlyRole(getRoleAdmin(role))
  {
    _setRoleNominee(role, account, false);
  }

  function getRoleAdminNominee(bytes32 role)
    public
    view
    virtual
    override
    returns (bytes32)
  {
    return _roleToRoleAdminNominee[role];
  }

  function isNominated(bytes32 role, address account)
    public
    view
    virtual
    override
    returns (bool)
  {
    return _roleToAccountToNominated[role][account];
  }

  function _setRoleAdminNominee(bytes32 role, bytes32 newRoleAdminNominee)
    internal
    virtual
  {
    emit RoleAdminNomineeUpdate(
      _roleToRoleAdminNominee[role],
      newRoleAdminNominee
    );
    _roleToRoleAdminNominee[role] = newRoleAdminNominee;
  }

  function _setRoleNominee(
    bytes32 role,
    address account,
    bool nominationStatus
  ) internal virtual {
    _roleToAccountToNominated[role][account] = nominationStatus;
    emit RoleNomineeUpdate(role, account, nominationStatus);
  }
}

