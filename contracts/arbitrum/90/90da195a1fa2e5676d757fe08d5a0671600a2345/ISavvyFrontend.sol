// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "./ISavvyInfoAggregatorStructs.sol";

/// @title ISavvyFrontend
/// @author Savvy DeFi
///
/// @notice Get the necessary information for the Savvy DeFi frontend from a single call.
interface ISavvyFrontend is ISavvyInfoAggregatorStructs {
    /// @notice Add new SavvySwap.
    /// @dev Only owner can call this function. If not, return IllegalArgument().
    /// @param savvySwaps_ List of SavvySwap addresses.
    function setSavvySwap(
        address[] memory savvySwaps_,
        bool[] memory shouldAdd_
    ) external;

    /// @notice A simplified way to get all the information for the Dashboard
    /// page on the frontend.
    ///
    /// @notice `account_` must be a non-zero address or this call will revert with a {IllegalArgument} error.
    ///
    /// @param account_ The specific wallet to get information for.
    /// @return dashboardPageInfo The Dashboard information for an account.
    function getDashboardPageInfo(
        address account_
    ) external view returns (DashboardPageInfo memory);

    /// @notice A simplified way to get all the information for the Pools
    /// page on the frontend.
    ///
    /// @notice `account_` must be a non-zero address or this call will revert with a {IllegalArgument} error.
    ///
    /// @param account_ The specific wallet to get information for.
    /// @return poolsPageInfo The Pools information for an account.
    function getPoolsPageInfo(
        address account_
    ) external view returns (PoolsPageInfo memory);

    /// @notice A simplified way to get all the information for the MySVY
    /// page on the frontend.
    ///
    /// @notice `account_` must be a non-zero address or this call will revert with a {IllegalArgument} error.
    ///
    /// @param account_ The specific wallet to get information for.
    /// @return MySVYPageInfo The MySVY information for an account.
    function getMySVYPageInfo(
        address account_
    ) external view returns (MySVYPageInfo memory);

    /// @notice Set new InfoAggregator contract address.
    /// @dev Only owner can call this function.
    /// @param infoAggregator_ The address of infoAggregator.
    function setInfoAggregator(address infoAggregator_) external;

    /// @notice A simplified way to get all the information for the Swap
    /// page on the frontend.
    ///
    /// @notice `account_` must be a non-zero address or this call will revert with a {IllegalArgument} error.
    ///
    /// @param account_ The specific wallet to get information for.
    /// @return MySVYPageInfo The Swap information for an account.
    function getSwapPageInfo(
        address account_
    ) external view returns (SwapPageInfo memory);
}

