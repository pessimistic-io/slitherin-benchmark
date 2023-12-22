// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity 0.8.15;

import {Authority} from "./AuthBase.sol";

/// @notice Interface for solmate's RolesAuthority.
/// @author Dinari (https://github.com/dinaricrypto/dinari-contracts/blob/main/contracts/security/IRolesAuthority.sol)
/// @dev Used for role based whitelisting
interface IRolesAuthority is Authority {
    function getUserRoles(address user) external view returns (bytes32);

    function isCapabilityPublic(address target, bytes4 functionSig) external view returns (bool);

    function getRolesWithCapability(address target, bytes4 functionSig) external view returns (bytes32);

    function doesUserHaveRole(address user, uint8 role) external view returns (bool);

    function doesRoleHaveCapability(
        uint8 role,
        address target,
        bytes4 functionSig
    ) external view returns (bool);

    function setPublicCapability(
        address target,
        bytes4 functionSig,
        bool enabled
    ) external;

    function setRoleCapability(
        uint8 role,
        address target,
        bytes4 functionSig,
        bool enabled
    ) external;

    function setUserRole(
        address user,
        uint8 role,
        bool enabled
    ) external;
}

