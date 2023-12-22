// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IDeriLens {
    struct PriceAndVolatility {
        string symbol;
        int256 indexPrice;
        int256 volatility;
    }

    struct PoolInfo {
        address pool;
        address implementation;
        address protocolFeeCollector;
        address tokenB0;
        address tokenWETH;
        address vTokenB0;
        address vTokenETH;
        address lToken;
        address pToken;
        address oracleManager;
        address swapper;
        address symbolManager;
        uint256 reserveRatioB0;
        int256 minRatioB0;
        int256 poolInitialMarginMultiplier;
        int256 protocolFeeCollectRatio;
        int256 minLiquidationReward;
        int256 maxLiquidationReward;
        int256 liquidationRewardCutRatio;
        int256 liquidity;
        int256 lpsPnl;
        int256 cumulativePnlPerLiquidity;
        int256 protocolFeeAccrued;
        address symbolManagerImplementation;
        int256 initialMarginRequired;
    }

    struct MarketInfo {
        address underlying;
        address vToken;
        string underlyingSymbol;
        string vTokenSymbol;
        uint256 underlyingPrice;
        uint256 exchangeRate;
        uint256 vTokenBalance;
    }

    struct SymbolInfo {
        string category;
        string symbol;
        address symbolAddress;
        address implementation;
        address manager;
        address oracleManager;
        bytes32 symbolId;
        int256 feeRatio;
        int256 alpha;
        int256 fundingPeriod;
        int256 minTradeVolume;
        int256 minInitialMarginRatio;
        int256 initialMarginRatio;
        int256 maintenanceMarginRatio;
        int256 pricePercentThreshold;
        uint256 timeThreshold;
        bool isCloseOnly;
        bytes32 priceId;
        bytes32 volatilityId;
        int256 feeRatioITM;
        int256 feeRatioOTM;
        int256 strikePrice;
        bool isCall;
        int256 netVolume;
        int256 netCost;
        int256 indexPrice;
        uint256 fundingTimestamp;
        int256 cumulativeFundingPerVolume;
        int256 tradersPnl;
        int256 initialMarginRequired;
        uint256 nPositionHolders;
        int256 curIndexPrice;
        int256 curVolatility;
        int256 curCumulativeFundingPerVolume;
        int256 K;
        int256 markPrice;
        int256 funding;
        int256 timeValue;
        int256 delta;
        int256 u;
    }

    struct LpInfo {
        address account;
        uint256 lTokenId;
        address vault;
        int256 amountB0;
        int256 liquidity;
        int256 cumulativePnlPerLiquidity;
        uint256 vaultLiquidity;
        MarketInfo[] markets;
    }

    struct TdInfo {
        address account;
        uint256 pTokenId;
        address vault;
        int256 amountB0;
        uint256 vaultLiquidity;
        MarketInfo[] markets;
        PositionInfo[] positions;
    }

    struct PositionInfo {
        address symbolAddress;
        string symbol;
        int256 volume;
        int256 cost;
        int256 cumulativeFundingPerVolume;
    }

    function everlastingOptionPricingLens() external view returns (address);

    function getInfo(
        address pool_,
        address account_,
        PriceAndVolatility[] memory pvs
    )
        external
        view
        returns (
            PoolInfo memory poolInfo,
            MarketInfo[] memory marketsInfo,
            SymbolInfo[] memory symbolsInfo,
            LpInfo memory lpInfo,
            TdInfo memory tdInfo
        );

    function getLpInfo(address pool_, address account_) external view returns (LpInfo memory info);

    function getMarketsInfo(address pool_) external view returns (MarketInfo[] memory infos);

    function getPoolInfo(address pool_) external view returns (PoolInfo memory info);

    function getSymbolsInfo(address pool_, PriceAndVolatility[] memory pvs)
        external
        view
        returns (SymbolInfo[] memory infos);

    function getTdInfo(address pool_, address account_) external view returns (TdInfo memory info);

    function nameId() external view returns (bytes32);

    function versionId() external view returns (bytes32);
}

