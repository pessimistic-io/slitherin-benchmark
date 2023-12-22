// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

/// @title IAaveLogicLens - AaveLogicLens interface
interface IAaveLogicLens {
    // =========================
    // View Functions
    // =========================

    /// @notice Fetches the supply amount of a specific token for a given user from Aave V3
    /// @param supplyToken: The token address for which supply amount is to be fetched
    /// @param user: The address of the user
    /// @return The supply amount of the token for the user
    function getSupplyAmount(
        address supplyToken,
        address user
    ) external view returns (uint256);

    /// @notice Fetches the total debt amount of a specific token for a given user from Aave V3
    /// @param debtToken: The token address for which debt amount is to be fetched
    /// @param user: The address of the user
    /// @return The total debt amount of the token for the user
    function getTotalDebt(
        address debtToken,
        address user
    ) external view returns (uint256);

    /// @notice Fetches the current health factor for a given user from Aave V3
    /// @param user: The address of the user
    /// @return currentHF The current health factor for the user
    function getCurrentHF(
        address user
    ) external view returns (uint256 currentHF);

    /// @notice Fetches the liquidation threshold for a specific token from Aave V3
    /// @param token: The token address for which the liquidation threshold is to be fetched
    /// @return currentLiquidationThreshold_1e4 The liquidation threshold for the token
    function getCurrentLiquidationThreshold(
        address token
    ) external view returns (uint256 currentLiquidationThreshold_1e4);
}

