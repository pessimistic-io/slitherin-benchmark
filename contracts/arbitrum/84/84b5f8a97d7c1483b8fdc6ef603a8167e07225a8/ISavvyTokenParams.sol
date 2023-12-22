// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

/// @title  ISavvyTokenParams
/// @author Savvy DeFi
interface ISavvyTokenParams {
    /// @notice Defines base token parameters.
    struct BaseTokenParams {
        // A coefficient used to normalize the token to a value comparable to the debt token. For example, if the
        // base token is 8 decimals and the debt token is 18 decimals then the conversion factor will be
        // 10^10. One unit of the base token will be comparably equal to one unit of the debt token.
        uint256 conversionFactor;
        // The number of decimals the token has. This value is cached once upon registering the token so it is important
        // that the decimals of the token are immutable or the system will begin to have computation errors.
        uint8 decimals;
        // A flag to indicate if the token is enabled.
        bool enabled;
    }

    /// @notice Defines yield token parameters.
    struct YieldTokenParams {
        // The maximum percentage loss that is acceptable before disabling certain actions.
        uint256 maximumLoss;
        // The maximum value of yield tokens that the system can hold, measured in units of the base token.
        uint256 maximumExpectedValue;
        // The percent of credit that will be unlocked per block. The representation of this value is a 18  decimal
        // fixed point integer.
        uint256 creditUnlockRate;
        // The current balance of yield tokens which are held by users.
        uint256 activeBalance;
        // The current balance of yield tokens which are earmarked to be harvested by the system at a later time.
        uint256 harvestableBalance;
        // The total number of shares that have been borrowed for this token.
        uint256 totalShares;
        // The expected value of the tokens measured in base tokens. This value controls how much of the token
        // can be harvested. When users deposit yield tokens, it increases the expected value by how much the tokens
        // are exchangeable for in the base token. When users withdraw yield tokens, it decreases the expected
        // value by how much the tokens are exchangeable for in the base token.
        uint256 expectedValue;
        // The current amount of credit which is will be distributed over time to depositors.
        uint256 pendingCredit;
        // The amount of the pending credit that has been distributed.
        uint256 distributedCredit;
        // The block number which the last credit distribution occurred.
        uint256 lastDistributionBlock;
        // The total accrued weight. This is used to calculate how much credit a user has been granted over time. The
        // representation of this value is a 18 decimal fixed point integer.
        uint256 accruedWeight;
        // The associated base token that can be redeemed for the yield-token.
        address baseToken;
        // The adapter used by the system to wrap, unwrap, and lookup the conversion rate of this token into its
        // base token.
        address adapter;
        // The number of decimals the token has. This value is cached once upon registering the token so it is important
        // that the decimals of the token are immutable or the system will begin to have computation errors.
        uint8 decimals;
        // A flag to indicate if the token is enabled.
        bool enabled;
    }
}

