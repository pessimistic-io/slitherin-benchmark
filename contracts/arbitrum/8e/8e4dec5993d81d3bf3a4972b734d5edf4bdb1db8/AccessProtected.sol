// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import "./Context.sol";
import "./Ownable.sol";

/** 
@title Access Limiter to multiple owner-specified accounts.
@dev Exposes the onlyAdmin modifier, which will revert (ADMIN_ACCESS_REQUIRED) if the caller is not the owner nor the admin.
@notice An address with the role admin can grant that role to or revoke that role from any address via the function setAdmin().
*/
abstract contract AccessProtected is Context {
    mapping(address => bool) private _admins; // user address => admin? mapping
    uint public adminCount;

    event AdminAccessSet(address indexed _admin, bool _enabled);

    constructor() {
        _admins[_msgSender()] = true;
        adminCount = 1;
        emit AdminAccessSet(_msgSender(), true);
    }

    /**
     * Throws if called by any account that isn't an admin or an owner.
     */
    modifier onlyAdmin() {
        require(_admins[_msgSender()], "ADMIN_ACCESS_REQUIRED");
        _;
    }

    function isAdmin(address _addressToCheck) external view returns (bool) {
        return _admins[_addressToCheck];
    }

    /**
     * @notice Set/unset Admin Access for a given address.
     *
     * @param admin - Address of the new admin (or the one to be removed)
     * @param isEnabled - Enable/Disable Admin Access
     */
    function setAdmin(address admin, bool isEnabled) public onlyAdmin {
        require(admin != address(0), "INVALID_ADDRESS");
        require(_admins[admin] != isEnabled, "FLAG_ALREADY_PRESENT_FOR_ADDRESS");

        if (isEnabled) {
            adminCount++;
        } else {
            require(adminCount > 1, "AT_LEAST_ONE_ADMIN_REQUIRED");
            adminCount--;
        }

        _admins[admin] = isEnabled;
        emit AdminAccessSet(admin, isEnabled);
    }
}
