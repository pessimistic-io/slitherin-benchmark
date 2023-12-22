// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

/// @title IDexCheckerLogicBase - DexCheckerLogicBase interface.
/// @dev This interface provides the structure for the DexChecker logic and its storage components.
interface IDexCheckerLogicBase {
    // =========================
    // Storage
    // =========================

    /// @dev Structure that represents the storage for DexChecker.
    /// @param nftId The ID of the NFT associated with the DexChecker.
    /// @param initialized A boolean indicating if the DexChecker has been initialized or not.
    struct DexCheckerStorage {
        uint256 nftId;
        bool initialized;
    }

    // =========================
    // Events
    // =========================

    /// @notice Emits when the DexChecker is initialized.
    event DexCheckerInitialized();

    // =========================
    // Errors
    // =========================

    /// @notice Error thrown when the DexChecker has not been initialized.
    error DexChecker_NotInitialized();

    /// @notice Error thrown when the DexChecker has already been initialized.
    error DexChecker_AlreadyInitialized();
}

