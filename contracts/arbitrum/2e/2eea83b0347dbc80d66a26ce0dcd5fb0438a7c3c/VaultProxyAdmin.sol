// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IUpgradeLogic} from "./IUpgradeLogic.sol";

import {IVaultFactory} from "./IVaultFactory.sol";
import {IVaultProxyAdmin} from "./IVaultProxyAdmin.sol";

/// @title VaultProxyAdmin
/// @notice This contract is a common proxy admin for all vaults deployed via factory.
/// @dev Through this contract, all vaults can be updated to a new implementation.
contract VaultProxyAdmin is IVaultProxyAdmin {
    // =========================
    // Storage
    // =========================

    IVaultFactory public immutable vaultFactory;

    constructor(address _vaultFactory) {
        vaultFactory = IVaultFactory(_vaultFactory);
    }

    // =========================
    // Vault implementation logic
    // =========================

    /// @inheritdoc IVaultProxyAdmin
    function initializeImplementation(
        address vault,
        address implementation
    ) external {
        if (msg.sender != address(vaultFactory)) {
            revert VaultProxyAdmin_CallerIsNotFactory();
        }

        IUpgradeLogic(vault).upgrade(implementation);
    }

    /// @inheritdoc IVaultProxyAdmin
    function upgrade(address vault, uint256 version) external {
        if (IUpgradeLogic(vault).owner() != msg.sender) {
            revert VaultProxyAdmin_SenderIsNotVaultOwner();
        }

        if (version > vaultFactory.versions() || version == 0) {
            revert VaultProxyAdmin_VersionDoesNotExist();
        }

        address currentImplementation = IUpgradeLogic(vault).implementation();
        address implementation = vaultFactory.implementation(version);

        if (currentImplementation == implementation) {
            revert VaultProxyAdmin_CannotUpdateToCurrentVersion();
        }

        IUpgradeLogic(vault).upgrade(implementation);
    }
}

