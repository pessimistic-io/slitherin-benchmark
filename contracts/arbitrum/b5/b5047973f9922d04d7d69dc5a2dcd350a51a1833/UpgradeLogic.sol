// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IUpgradeLogic} from "./IUpgradeLogic.sol";

import {AccessControlLib} from "./AccessControlLib.sol";

/// @title UpgradeLogic
/// @dev Logic for upgrading the implementation of a proxy clone contract.
contract UpgradeLogic is IUpgradeLogic {
    // =========================
    // Main functions
    // =========================

    /// @inheritdoc IUpgradeLogic
    function upgrade(address newImplementation) external {
        assembly ("memory-safe") {
            sstore(not(0), newImplementation)
        }
        emit ImplementationChanged(newImplementation);
    }

    /// @inheritdoc IUpgradeLogic
    function implementation() external view returns (address impl_) {
        assembly ("memory-safe") {
            impl_ := sload(not(0))
        }
    }

    /// @inheritdoc IUpgradeLogic
    function owner() external view returns (address) {
        return AccessControlLib.getOwner();
    }
}

