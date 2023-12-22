// SPDX-License-Identifier: None
pragma solidity 0.8.10;
import "./console.sol";

library LibAccessControl {
    /// @notice Access Control Roles
    // TODO: We might want keccak hashes instead
    enum Roles {
        NULL,
        FORGER,
        BORIS,
        ADMIN
    }
}

