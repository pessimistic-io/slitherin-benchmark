// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.19;

/// @dev DataTypes.sol defines the Token struct data types used in the TokenStorage layout

/// @dev represents data related to $MINT token accruals (linked to a specific account)
struct AccrualData {
    /// @dev last ratio an account had when one of their actions led to a change in the
    /// reservedSupply
    uint256 offset;
    /// @dev amount of tokens accrued as a result of distribution to token holders
    uint256 accruedTokens;
}

