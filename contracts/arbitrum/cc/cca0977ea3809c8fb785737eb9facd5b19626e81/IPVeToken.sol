// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity 0.8.17;

interface IPVeToken {
    // ============= USER INFO =============

    /// @notice Returns the user's vePENDLE balance which decreases linearly on a weekly basis.
    function balanceOf(address user) external view returns (uint128);

    /// @notice Returns the total supply as it was last updated.
    /// There are two cases:
    /// - On Ethereum, this number will be updated once a week after any write actions to vePENDLE by anyone.
    /// - On Arbitrum, this number will always be equal to totalSupplyCurrent().
    function positionData(address user) external view returns (uint128 amount, uint128 expiry);

    // ============= META DATA =============

    /// @notice Returns the totalSupply last it was updated. There are 2 cases:
    /// - On Ethereum, this number will be updated once a week after any write actions to vePENDLE
    /// by anyone
    /// - On Arbitrum, this number will always be equal to totalSupplyCurrent();
    function totalSupplyStored() external view returns (uint128);

    /// @notice Decays the total supply of vePENDLE weekly and returns the most up-to-date value.
    /// The only time this function will return a different value from totalSupplyStored() is if
    /// it is on Ethereum and there have been no write actions to vePENDLE for the current week.
    function totalSupplyCurrent() external returns (uint128);

    /// @notice Aggregates two numbers to save gas
    function totalSupplyAndBalanceCurrent(address user) external returns (uint128, uint128);
}

