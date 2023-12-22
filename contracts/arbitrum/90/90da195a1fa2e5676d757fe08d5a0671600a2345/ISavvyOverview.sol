// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "./ISavvyInfoAggregatorStructs.sol";

interface ISavvyOverview {
    /// @notice Return total debt amount calculated in USD.
    /// @return Total debt amount calculated in USD.
    function getTotalDebtAmount() external view returns (int256);

    /// @notice Return total deposited amount calculated in USD.
    /// @return Total deposited amount calculated in USD.
    function getTotalDepositedAmount() external view returns (uint256);

    /// @notice Return total value locked (TVL) calculated in USD.
    /// @return Total total deposited amount plus SVY staked in veSVY in USD.
    function getTotalValueLocked() external view returns (uint256);

    /// @notice Get total SVY staked in veSVY.
    /// @return Total amount of SVY staked in veSVY.
    function getTotalSVYStaked() external view returns (uint256);

    /// @notice Get total SVY staked in veSVY in USD.
    /// @return The USD value of SVY staked in veSVY.
    function getTotalSVYStakedUSD() external view returns (uint256);

    /// @notice Get total available credit.
    /// @return Total amount of available credit calculated in USD.
    function getAvailableCredit() external view returns (int256);

    /// @notice Get all token price that added to Savvy DeFi
    /// @return Token price informations.
    function getAllTokenPrice()
        external
        view
        returns (ISavvyInfoAggregatorStructs.TokenPriceData[] memory);
}

