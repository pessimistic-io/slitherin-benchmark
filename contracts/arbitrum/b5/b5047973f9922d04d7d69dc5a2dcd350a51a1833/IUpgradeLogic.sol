// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

/// @title IUpgradeLogic - UpgradeLogicinterface
/// @dev Logic for upgrading the implementation of a proxy clone contract.
interface IUpgradeLogic {
    // =========================
    // Events
    // =========================

    /// @notice Emits when the implementation address is changed.
    /// @param newImplementation The address of the new implementation.
    event ImplementationChanged(address newImplementation);

    // =========================
    // Main functions
    // =========================

    /// @notice Setting a `newImplementation` address for delegate calls
    /// from the proxy clone.
    /// @param newImplementation Address of the new implementation.
    function upgrade(address newImplementation) external;

    /// @notice Returns the address of the current implementation to which
    /// the proxy clone delegates calls.
    /// @return impl_ Address of the current implementation.
    function implementation() external view returns (address impl_);

    /// @notice Returns the address of the current owner of the vault.
    /// @return The address of the current owner.
    function owner() external view returns (address);
}

