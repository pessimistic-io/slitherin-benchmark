// SPDX-License-Identifier: None
pragma solidity 0.8.18;

library LibAccessControl {
    /// @notice Access Control Roles
    enum Roles {
        NULL,
        TOKEN_MANAGER,
        ADMIN,
        MINTER
    }
}

