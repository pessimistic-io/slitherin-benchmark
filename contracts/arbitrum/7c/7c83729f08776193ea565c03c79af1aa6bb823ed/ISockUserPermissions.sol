// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

/**
 * Aggregated Signatures validator.
 */
interface ISockUserPermissions {

    struct UserPermission {
        bool allowed;
        bool isPayable;
    }

    function setUserPermissions(
        uint256[] memory permissionIndexs,
        bool[] memory alloweds,
        bool[] memory isPayables
    ) external;

}

