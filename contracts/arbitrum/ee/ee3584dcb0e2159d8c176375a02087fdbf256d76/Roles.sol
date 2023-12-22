// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity 0.8.15;

import {IRolesAuthority} from "./IRolesAuthority.sol";

/// @notice Extensions for RolesAuthority.
/// @author Dinari (https://github.com/dinaricrypto/dinari-contracts/blob/main/contracts/libraries/Roles.sol)
library Roles {
    error Roles__MissingRole(address account, address target, uint8 role);

    uint8 public constant TERM_ROLE = 31;
    uint8 public constant PAYMENT_TOKEN_ROLE = 32;

    function checkUserRole(
        IRolesAuthority authority,
        address account,
        uint8 role
    ) internal view {
        if (!authority.doesUserHaveRole(account, role)) revert Roles__MissingRole(account, address(this), role);
    }
}

