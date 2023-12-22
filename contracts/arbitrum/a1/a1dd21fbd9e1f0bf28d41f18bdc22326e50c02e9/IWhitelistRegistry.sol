// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.12;

interface IWhitelistRegistry {
    event PermissionsAdded(
        address whitelistManager,
        address vault,
        address[] addressesAdded
    );
    event PermissionsRemoved(
        address whitelistManager,
        address vault,
        address[] addressesRemoved
    );
    event ManagerAdded(address vaultAddress, address manager);

    function addPermissions(
        address _vaultAddress,
        address[] calldata _addresses
    ) external;

    function registerWhitelistManager(address manager) external;

    function revokePermissions(
        address _vaultAddress,
        address[] calldata _addresses
    ) external;
}

