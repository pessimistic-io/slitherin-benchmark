// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IDexCheckerLogicBase} from "./IDexCheckerLogicBase.sol";

/// @title IDexCheckerLogicUniswap - Interface for the DexChecker logic specific to Uniswap.
/// @dev This interface extends IDexCheckerLogicBase and provides methods for Uniswap specific operations.
interface IDexCheckerLogicUniswap is IDexCheckerLogicBase {
    // =========================
    // Initializer
    // =========================

    /// @notice Initializes the DexChecker for Uniswap.
    /// @param nftId The ID of the NFT to be associated with the DexChecker.
    /// @param pointer Pointer to the storage location.
    function uniswapDexCheckerInitialize(
        uint256 nftId,
        bytes32 pointer
    ) external;

    // =========================
    // Main functions
    // =========================

    /// @notice Checks if the price is out of the allowed tick range on Uniswap.
    /// @param pointer Pointer to the storage location.
    /// @return A boolean indicating if the price is out of the tick range.
    function uniswapCheckOutOfTickRange(
        bytes32 pointer
    ) external view returns (bool);

    /// @notice Checks if the price is in the allowed tick range on Uniswap.
    /// @param pointer Pointer to the storage location.
    /// @return A boolean indicating if the price is in the tick range.
    function uniswapCheckInTickRange(
        bytes32 pointer
    ) external view returns (bool);

    /// @notice Checks if fees exist for a given token pair on Uniswap.
    /// @param pointer Pointer to the storage location.
    /// @return A boolean indicating if fees exist.
    function uniswapCheckFeesExistence(
        bytes32 pointer
    ) external view returns (bool);

    // =========================
    // Getter
    // =========================

    /// @notice Retrieves the local DexChecker storage value for Uniswap.
    /// @param pointer Pointer to the storage location.
    /// @return The NFT ID associated with the DexChecker.
    function uniswapGetLocalDexCheckerStorage(
        bytes32 pointer
    ) external view returns (uint256);
}

