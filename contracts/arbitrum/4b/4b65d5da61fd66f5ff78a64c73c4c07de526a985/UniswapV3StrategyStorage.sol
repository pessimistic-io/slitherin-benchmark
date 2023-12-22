// SPDX-License-Identifier: BSL 1.1

pragma solidity ^0.8.17;

contract UniswapV3StrategyStorage {
    
    /**
     * @param leverage Leverage used to decide how much to borrow from LendVault
     * @param minLeverage The lowest that leverage will be taken to when LendVault requests delever
     * @param tick0 Lower tick for uniswap v3 liquidity range
     * @param tick1 Upper tick for uniswap v3 liquidity range
     */
    struct Parameters {
        uint leverage;
        uint minLeverage;
        uint maxLeverage;
        int24 tick0;
        int24 tick1;
    }

    /**
     * @param ammCheckThreshold The deviation threshold allowed between pool price and oracle price
     * @param slippage Slippage used when using swapper
     * @param healthThreshold Minimum health below which liquidity position is exited
     */
    struct Thresholds {
        uint ammCheckThreshold;
        uint slippage;
        uint healthThreshold;
    }

    /**
     * @notice Important addresses related to Uniswap
     * @param want The address of the liquidity pool used for farming
     * @param stableToken The stable token from the liquidity pool
     * @param volatileToken The volatile token from the liquidity pool
     * @param positionsManager Uniswap v3 NFT positions manager
     */
    struct Addresses {
        address want;
        address stableToken;
        address volatileToken;
        address positionsManager;
    }

    Addresses public addresses;

    Thresholds public thresholds;

    Parameters public parameters;

    /// @notice Token id in uniswap v3 NFT position manager
    uint public positionId;

    /// @notice The price anchor that is set on every rebalance
    uint public priceAnchor;

    /// @notice The total amount of rewards that have been harvested since inception in terms of stable token
    uint public harvested;

    /// @notice The number of times that the strategy has been rebalanced
    uint public numRebalances;

    /// @notice The amount of the vault's deposit token that has been withdrawn from the strategy
    uint public withdrawn;

    // ---------- Previous transcation trackers ----------

    /// @notice Internal variable used to calculate the price change impact
    int public prevBalance;

    /// @notice The amount of tokens deposited from the vault until the latest transaction
    uint public prevDeposited;

    /// @notice The previous value of the debts expressed in terms of the vault's deposit token
    uint public prevDebt;

    /// @notice The harvestable amount expressed in stable token at the last transaction
    int public prevHarvestable;

    // ---------- PNLs ----------

    /// @notice The impact that swapping tokens has had on the strategy's pnl
    int public slippageImpact;

    /// @notice The change in the strategy's balance due to the change in the volatile token's price
    int public unrealizedPriceChangeImpact;

    /// @notice The unrealized price change impact that has become realized due to withdrawals
    int public realizedPriceChangeImpact;

    /// @notice Mapping from tokens to interest paid for borrowing the token
    mapping (address=>int) public interestPayments;

    /// @notice The interest payments for a token expressed in terms of the vault's deposit token
    mapping (address=>int) public interestPaymentsInDepositToken;

    int cachedBalance;
    uint prevCacheUpdateBlock;

    // Token balances at the previous transaction
    mapping (address=>uint) public prevBalances;

    // Token debts at previous transaction
    mapping (address=>uint) public prevDebts;

    // Token debts at the last repay or borrow event
    mapping (address=>uint) public prevDebtsAtRepayBorrow;

    // TVL of the strategy at the previosu transaction
    int public prevTvl;
}
