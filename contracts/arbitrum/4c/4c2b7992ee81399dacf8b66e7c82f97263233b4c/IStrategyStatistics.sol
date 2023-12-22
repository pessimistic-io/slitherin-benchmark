// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

struct XTokenInfo {
    string symbol;
    address xToken;
    uint256 totalSupply;
    uint256 totalSupplyUSD;
    uint256 lendingAmount;
    uint256 lendingAmountUSD;
    uint256 borrowAmount;
    uint256 borrowAmountUSD;
    uint256 borrowLimit;
    uint256 borrowLimitUSD;
    uint256 underlyingBalance;
    uint256 priceUSD;
}

struct XTokenAnalytics {
    string symbol;
    address platformAddress;
    string underlyingSymbol;
    address underlyingAddress;
    uint256 underlyingDecimals;
    uint256 underlyingPrice;
    uint256 totalSupply;
    uint256 totalSupplyUSD;
    uint256 totalBorrows;
    uint256 totalBorrowsUSD;
    uint256 liquidity;
    uint256 collateralFactor;
    uint256 borrowApy;
    uint256 borrowRewardsApy;
    uint256 supplyApy;
    uint256 supplyRewardsApy;
}

struct StrategyStatistics {
    XTokenInfo[] xTokensStatistics;
    WalletInfo[] walletStatistics;
    uint256 lendingEarnedUSD;
    uint256 totalSupplyUSD;
    uint256 totalBorrowUSD;
    uint256 totalBorrowLimitUSD;
    uint256 borrowRate;
    uint256 storageAvailableUSD;
    int256 totalAmountUSD;
}

struct LbfStrategyStatistics {
    XTokenInfo[] xTokensStatistics;
    WalletInfo[] walletStatistics;
    uint256 lendingEarnedUSD;
    uint256 totalSupplyUSD;
    uint256 totalBorrowUSD;
    uint256 totalBorrowLimitUSD;
    uint256 borrowRate;
    uint256 storageAvailableUSD;
    StakedInfo[] stakedStatistics;
    uint256 stakedAmountUSD;
    uint256 farmingRewardsAmountUSD;
    int256 totalAmountUSD;
}

struct FarmingPairInfo {
    uint256 index;
    address lpToken;
    uint256 farmingAmount;
    uint256 rewardsAmount;
    uint256 rewardsAmountUSD;
}

struct WalletInfo {
    string symbol;
    address token;
    uint256 balance;
    uint256 balanceUSD;
}

struct PriceInfo {
    address token;
    uint256 priceUSD;
}

struct StakedTokenAmountUSD {
    address token;
    uint256 amount;
    uint256 amountUSD;
    uint256 fee;
    uint256 feeUSD;
}

struct StakedInfo {
    uint256 tokenId;
    StakedTokenAmountUSD token0Info;
    StakedTokenAmountUSD token1Info;
}

struct Pair {
    address pool;
    uint24 percentage;
    uint24 minPricePercentage;
    uint24 maxPricePercentage;
    uint160 sqrtPriceThreshold; // 2**96 * sqrt(percentage)
    uint256 tokenId;
}

enum DestroyMode {
    // Remove liquidity from all pairs based on percentages
    Proportional,
    // Remove maximum liquidity from pair by pair
    Greedy,
    // Remove all liquidity
    Full
}

interface IStrategyStatistics {
    function getXTokenInfo(address _asset, address comptroller)
        external
        view
        returns (XTokenAnalytics memory);

    function getXTokensInfo(address comptroller)
        external
        view
        returns (XTokenAnalytics[] memory);

    function getStrategyStatistics(address logic)
        external
        view
        returns (StrategyStatistics memory statistics);

    function getStrategyXTokenInfo(address xToken, address logic)
        external
        view
        returns (XTokenInfo memory tokenInfo);

    function getStrategyXTokenInfoCompact(address xToken, address logic)
        external
        view
        returns (
            uint256 totalSupply,
            uint256 borrowLimit,
            uint256 borrowAmount
        );

    function getRewardsTokenPrice(address comptroller, address rewardsToken)
        external
        view
        returns (uint256 priceUSD);

    function getEnteredMarkets(address comptroller, address logic)
        external
        view
        returns (address[] memory markets);
}

interface IFarmingStatistics {
    function getStakedPortfolio(address logic, address strategy)
        external
        view
        returns (StakedInfo[] memory);

    function getFarmingRewardsAmount(address logic, address strategy)
        external
        view
        returns (uint256);
}

