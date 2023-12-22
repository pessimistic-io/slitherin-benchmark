// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;
pragma abicoder v2;

interface IRoleCheckable {
    function grantRole(bytes32 role, address account) external;

    function revokeRole(bytes32 role, address account) external;

    /**
     * @dev Returns `true` if `account` has been granted `role`.
     */
    function hasRole(bytes32 role, address account)
        external
        view
        returns (bool);
}

