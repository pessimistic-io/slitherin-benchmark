// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IPairInfos {

    struct TradeInitialAccFees {
        uint256 rollover;
        int256 funding;
        bool openedAfterUpdate;
    }

    function tradeInitialAccFees(address, uint256, uint256) external view returns (TradeInitialAccFees memory);

    function maxNegativePnlOnOpenP() external view returns (uint256);

    function storeTradeInitialAccFees(address trader, uint256 pairIndex, uint256 index, bool long) external;

    function getTradePriceImpact(
        uint256 openPrice,
        uint256 pairIndex,
        bool long,
        uint256 openInterest
    )
        external
        view
        returns (
            uint256 priceImpactP,
            uint256 priceAfterImpact
        );

    function getTradeRolloverFee(
        address trader,
        uint256 pairIndex,
        uint256 index,
        uint256 collateral
    ) external view returns (uint256);

    function getTradeFundingFee(
        address trader,
        uint256 pairIndex,
        uint256 index,
        bool long,
        uint256 collateral,
        uint256 leverage
    )
        external
        view
        returns (
            int256  // Positive => Fee, Negative => Reward
        );

    function getTradeLiquidationPricePure(
        uint256 openPrice,
        bool long,
        uint256 collateral,
        uint256 leverage,
        uint256 rolloverFee,
        int256 fundingFee
    ) external pure returns (uint256);

    function getTradeLiquidationPrice(
        address trader,
        uint256 pairIndex,
        uint256 index,
        uint256 openPrice,
        bool long,
        uint256 collateral,
        uint256 leverage
    ) external view returns (uint256);

    function getTradeValue(
        address trader,
        uint256 pairIndex,
        uint256 index,
        bool long,
        uint256 collateral,
        uint256 leverage,
        int256 percentProfit,
        uint256 closingFee
    ) external returns (uint256);

    function manager() external view returns (address);
}

