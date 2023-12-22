// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface GNSPairInfosInterfaceV6 {
    // Trade initial acc fees
    struct TradeInitialAccFees {
        uint rollover; // 1e18 (DAI)
        int funding; // 1e18 (DAI)
        bool openedAfterUpdate;
    }

    function tradeInitialAccFees(address, uint, uint) external view returns (TradeInitialAccFees memory);

    function maxNegativePnlOnOpenP() external view returns (uint); // PRECISION (%)

    function storeTradeInitialAccFees(address trader, uint pairIndex, uint index, bool long) external;

    function getTradePriceImpact(
        uint openPrice, // PRECISION
        uint pairIndex,
        bool long,
        uint openInterest // 1e18 (DAI)
    )
        external
        view
        returns (
            uint priceImpactP, // PRECISION (%)
            uint priceAfterImpact // PRECISION
        );

    function getTradeRolloverFee(
        address trader,
        uint pairIndex,
        uint index,
        uint collateral // 1e18 (DAI)
    ) external view returns (uint);

    function getTradeFundingFee(
        address trader,
        uint pairIndex,
        uint index,
        bool long,
        uint collateral, // 1e18 (DAI)
        uint leverage
    )
        external
        view
        returns (
            int // 1e18 (DAI) | Positive => Fee, Negative => Reward
        );

    function getTradeLiquidationPricePure(
        uint openPrice, // PRECISION
        bool long,
        uint collateral, // 1e18 (DAI)
        uint leverage,
        uint rolloverFee, // 1e18 (DAI)
        int fundingFee // 1e18 (DAI)
    ) external pure returns (uint);

    function getTradeLiquidationPrice(
        address trader,
        uint pairIndex,
        uint index,
        uint openPrice, // PRECISION
        bool long,
        uint collateral, // 1e18 (DAI)
        uint leverage
    ) external view returns (uint); // PRECISION

    function getTradeValue(
        address trader,
        uint pairIndex,
        uint index,
        bool long,
        uint collateral, // 1e18 (DAI)
        uint leverage,
        int percentProfit, // PRECISION (%)
        uint closingFee // 1e18 (DAI)
    ) external returns (uint); // 1e18 (DAI)

    function manager() external view returns (address);
}

