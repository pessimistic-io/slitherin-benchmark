// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

/**
 * @custom:version 6
 */
interface IGNSPairInfos {
    struct PairParams {
        uint256 onePercentDepthAbove; // DAI
        uint256 onePercentDepthBelow; // DAI
        uint256 rolloverFeePerBlockP; // PRECISION (%)
        uint256 fundingFeePerBlockP; // PRECISION (%)
    }

    struct TradeInitialAccFees {
        uint256 rollover; // 1e18 (DAI)
        int256 funding; // 1e18 (DAI)
        bool openedAfterUpdate;
    }

    function pairParams(uint256) external view returns (PairParams memory);

    function tradeInitialAccFees(address, uint256, uint256) external view returns (TradeInitialAccFees memory);

    function maxNegativePnlOnOpenP() external view returns (uint256); // PRECISION (%)

    function storeTradeInitialAccFees(address trader, uint256 pairIndex, uint256 index, bool long) external;

    /**
     * @custom:deprecated
     * getTradePriceImpact has been moved to Borrowing Fees contract
     */
    function getTradePriceImpact(
        uint256 openPrice, // PRECISION
        uint256 pairIndex,
        bool long,
        uint256 openInterest // 1e18 (DAI)
    )
        external
        view
        returns (
            uint256 priceImpactP, // PRECISION (%)
            uint256 priceAfterImpact // PRECISION
        );

    function getTradeRolloverFee(
        address trader,
        uint256 pairIndex,
        uint256 index,
        uint256 collateral // 1e18 (DAI)
    ) external view returns (uint256);

    function getTradeFundingFee(
        address trader,
        uint256 pairIndex,
        uint256 index,
        bool long,
        uint256 collateral, // 1e18 (DAI)
        uint256 leverage
    )
        external
        view
        returns (
            int256 // 1e18 (DAI) | Positive => Fee, Negative => Reward
        );

    function getTradeLiquidationPricePure(
        uint256 openPrice, // PRECISION
        bool long,
        uint256 collateral, // 1e18 (DAI)
        uint256 leverage,
        uint256 rolloverFee, // 1e18 (DAI)
        int256 fundingFee // 1e18 (DAI)
    ) external pure returns (uint256);

    function getTradeLiquidationPrice(
        address trader,
        uint256 pairIndex,
        uint256 index,
        uint256 openPrice, // PRECISION
        bool long,
        uint256 collateral, // 1e18 (DAI)
        uint256 leverage
    ) external view returns (uint256); // PRECISION

    function getTradeValue(
        address trader,
        uint256 pairIndex,
        uint256 index,
        bool long,
        uint256 collateral, // 1e18 (DAI)
        uint256 leverage,
        int256 percentProfit, // PRECISION (%)
        uint256 closingFee // 1e18 (DAI)
    ) external returns (uint256); // 1e18 (DAI)

    function manager() external view returns (address);
}

