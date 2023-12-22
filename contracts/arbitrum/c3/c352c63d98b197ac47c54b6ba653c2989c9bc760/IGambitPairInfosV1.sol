// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IGambitPairInfosV1 {
    function maxNegativePnlOnOpenP() external view returns (uint); // PRECISION (%)

    function storeTradeInitialAccFees(
        address trader,
        uint pairIndex,
        uint index,
        bool long
    ) external;

    function getTradePriceImpact(
        uint openPrice, // PRECISION
        uint pairIndex,
        bool long,
        uint openInterest // 1e6 (USDC)
    )
        external
        view
        returns (
            uint priceImpactP, // PRECISION (%)
            uint priceAfterImpact // PRECISION
        );

    function getTradeLiquidationPrice(
        address trader,
        uint pairIndex,
        uint index,
        uint openPrice, // PRECISION
        bool long,
        uint collateral, // 1e6 (USDC)
        uint leverage
    ) external view returns (uint); // PRECISION

    function getTradeValue(
        address trader,
        uint pairIndex,
        uint index,
        bool long,
        uint collateral, // 1e6 (USDC)
        uint leverage,
        int percentProfit, // PRECISION (%)
        uint closingFee // 1e6 (USDC)
    ) external returns (uint); // 1e6 (USDC)

    function getOpenPnL(
        uint pairIndex,
        uint currentPrice // 1e10
    ) external view returns (int pnl);

    function getOpenPnLSide(
        uint pairIndex,
        uint currentPrice, // 1e10
        bool buy // true = long, false = short
    ) external view returns (int pnl);

    struct ExposureCalcParamsStruct {
        uint pairIndex;
        bool buy;
        uint positionSizeUsdc;
        uint leverage;
        uint currentPrice; // 1e10
        uint openPrice; // 1e10
    }

    function isWithinExposureLimits(
        ExposureCalcParamsStruct memory params
    ) external view returns (bool);

    function manager() external view returns (address);
}

