// SPDX-License-Identifier: BUSL-1.1

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

    /// @notice The impact that rebalancing has had on the strategy's pnl
    /// @dev Rebalancing includes calling rebalance, setTicks, setLeverage and delever
    int public rebalanceImpact;

    /// @notice The impact that swapping tokens has had on the strategy's pnl
    int public slippageImpact;

    /// @notice The impact that interest payments to the lending module have had on the strategy's pnl
    int public interestPaymentImpact;

    /// @notice The impact that the changing price has had on the strategy's pnl
    int public priceChangeImpact;

    /// @notice Internal variable used to calculate the price change impact
    int internal balancePrev;

    /// @notice Internal variable to track the last block at which cachedBalance was updated
    uint internal prevCacheUpdateBlock;

    /// @notice cachedBalance used to optimize gas consumption since calculating balance is expensive
    int internal cachedBalance;
}
