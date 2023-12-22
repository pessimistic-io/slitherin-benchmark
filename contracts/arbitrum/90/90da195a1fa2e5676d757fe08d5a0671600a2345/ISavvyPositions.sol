// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "./ISavvyInfoAggregatorStructs.sol";

interface ISavvyPositions is ISavvyInfoAggregatorStructs {
    /// @notice Total balance of each token type in user’s wallet
    /// @param user_ The address of a user.
    /// @return Infos for each pool, each token.
    function getAvailableDepositTokenAmount(
        address user_
    ) external view returns (SavvyPosition[] memory);

    /// @notice Total deposited into each pool of each token type for user.
    /// @param user_ The address of a user.
    /// @return Infos for each pool, each token.
    function getTotalDepositedTokenAmount(
        address user_
    ) external view returns (SavvyPosition[] memory);

    /// @notice Total debt borrowed of each pool of each token type for user.
    /// @param user_ The address of a user.
    /// @return Infos for each pool, each token.
    function getTotalDebtTokenAmount(
        address user_
    ) external view returns (DebtInfo[] memory);

    /// @notice Up to 50% of deposit available to borrow as debt is reduced
    /// @notice  over time of each pool of each token type for user.
    /// @param user_ The address of a user.
    /// @return Infos for each pool, each token.
    function getAvailableCreditToken(
        address user_
    ) external view returns (DebtInfo[] memory);

    /// @notice Get the borrowable amount per SavvyPositionManager.
    /// @param user_ The address of a user.
    /// @return borrowableAmounts The borrowable amounts per SavvyPositionManager.
    function getBorrowableAmount(
        address user_
    ) external view returns (SavvyPosition[] memory);

    /// @notice Get the withdrawable amount per SavvyPositionManager.
    /// @param user_ The address of a user.
    /// @return The withdrawable amounts per SavvyPositionManager per YieldToken.
    function getWithdrawableAmount(
        address user_
    ) external view returns (SavvyWithdrawInfo[] memory);
}

