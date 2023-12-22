// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IVaultFactory} from "./IVaultFactory.sol";
import {BaseContract} from "./BaseContract.sol";

import {IVersionUpgradeLogic} from "./IVersionUpgradeLogic.sol";

/// @title VersionUpgradeLogic
/// @dev Logic for upgrading the version on vault.
contract VersionUpgradeLogic is IVersionUpgradeLogic, BaseContract {
    // =========================
    // Constructor
    // =========================

    IVaultFactory private immutable _vaultFactory;

    constructor(IVaultFactory vaultFactory) {
        _vaultFactory = vaultFactory;
    }

    // =========================
    // Main functions
    // =========================

    /// @inheritdoc IVersionUpgradeLogic
    function upgradeVersion(uint256 vaultVersion) external onlyVaultItself {
        if (vaultVersion > _vaultFactory.versions() || vaultVersion == 0) {
            revert VersionUpgradeLogic_VersionDoesNotExist();
        }

        address implementation = _vaultFactory.implementation(vaultVersion);
        address oldImplementation;
        assembly ("memory-safe") {
            oldImplementation := sload(not(0))
        }

        if (oldImplementation == implementation) {
            revert VersionUpgradeLogic_CannotUpdateToCurrentVersion();
        }

        assembly ("memory-safe") {
            sstore(not(0), implementation)
        }

        emit ImplementationChanged(implementation);
    }
}

