// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

interface ISavvyUserPortfolio {
    /// @notice Return total amount of user deposited calculated by USD.
    /// @param user_ The address of user to get total deposited amount.
    /// @return The amount of total deposited calculated by USD.
    function getUserDepositedAmount(
        address user_
    ) external view returns (uint256);

    /// @notice Get total available credit of a specific user.
    /// @dev Calculated as [total deposit] / [minimumCollateralization] - [current balance]
    /// @return Total amount of available credit of a specific user, calculated by USD.
    function getUserAvailableCredit(
        address user_
    ) external view returns (int256);

    /// @notice Return total debt amount calculated by USD.
    /// @param user_ The address of user to get total deposited amount.
    /// @return Total debt amount calculated by USD.
    function getUserDebtAmount(address user_) external view returns (int256);
}

