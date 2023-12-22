// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.9;

import { IERC20 } from "./IERC20.sol";
import { IPriceFeed } from "./IPriceFeed.sol";

interface IAmm {
    /**
     * @notice asset direction, used in getQuotePrice, getBasePrice, swapInput and swapOutput
     * @param ADD_TO_AMM add asset to Amm
     * @param REMOVE_FROM_AMM remove asset from Amm
     */
    enum Dir {
        ADD_TO_AMM,
        REMOVE_FROM_AMM
    }

    function swapInput(
        Dir _dir,
        uint256 _amount,
        bool _isQuote,
        bool _canOverFluctuationLimit
    )
        external
        returns (
            uint256 quoteAssetAmount,
            int256 baseAssetAmount,
            uint256 spreadFee,
            uint256 tollFee
        );

    function swapOutput(
        Dir _dir,
        uint256 _amount,
        bool _isQuote,
        bool _canOverFluctuationLimit
    )
        external
        returns (
            uint256 quoteAssetAmount,
            int256 baseAssetAmount,
            uint256 spreadFee,
            uint256 tollFee
        );

    function repegCheck(uint256 budget)
        external
        returns (
            bool,
            int256,
            uint256,
            uint256
        );

    function adjust(uint256 _quoteAssetReserve, uint256 _baseAssetReserve) external;

    function shutdown() external;

    function settleFunding(uint256 _cap)
        external
        returns (
            int256 premiumFractionLong,
            int256 premiumFractionShort,
            int256 fundingPayment
        );

    function calcFee(uint256 _quoteAssetAmount) external view returns (uint256, uint256);

    //
    // VIEW
    //

    function getFormulaicUpdateKResult(int256 budget)
        external
        view
        returns (
            bool isAdjustable,
            int256 cost,
            uint256 newQuoteAssetReserve,
            uint256 newBaseAssetReserve
        );

    function getMaxKDecreaseRevenue(uint256 _quoteAssetReserve, uint256 _baseAssetReserve) external view returns (int256 revenue);

    function isOverFluctuationLimit(Dir _dirOfBase, uint256 _baseAssetAmount) external view returns (bool);

    function getQuoteTwap(Dir _dir, uint256 _quoteAssetAmount) external view returns (uint256);

    function getBaseTwap(Dir _dir, uint256 _baseAssetAmount) external view returns (uint256);

    function getQuotePrice(Dir _dir, uint256 _quoteAssetAmount) external view returns (uint256);

    function getBasePrice(Dir _dir, uint256 _baseAssetAmount) external view returns (uint256);

    function getQuotePriceWithReserves(
        Dir _dir,
        uint256 _quoteAssetAmount,
        uint256 _quoteAssetPoolAmount,
        uint256 _baseAssetPoolAmount
    ) external pure returns (uint256);

    function getBasePriceWithReserves(
        Dir _dir,
        uint256 _baseAssetAmount,
        uint256 _quoteAssetPoolAmount,
        uint256 _baseAssetPoolAmount
    ) external pure returns (uint256);

    function getSpotPrice() external view returns (uint256);

    // overridden by state variable

    function initMarginRatio() external view returns (uint256);

    function maintenanceMarginRatio() external view returns (uint256);

    function liquidationFeeRatio() external view returns (uint256);

    function partialLiquidationRatio() external view returns (uint256);

    function quoteAsset() external view returns (IERC20);

    function priceFeedKey() external view returns (bytes32);

    function tradeLimitRatio() external view returns (uint256);

    function fundingPeriod() external view returns (uint256);

    function priceFeed() external view returns (IPriceFeed);

    function getReserve() external view returns (uint256, uint256);

    function open() external view returns (bool);

    function adjustable() external view returns (bool);

    function canLowerK() external view returns (bool);

    function ptcKIncreaseMax() external view returns (uint256);

    function ptcKDecreaseMax() external view returns (uint256);

    function getSettlementPrice() external view returns (uint256);

    function getCumulativeNotional() external view returns (int256);

    function getBaseAssetDelta() external view returns (int256);

    function getUnderlyingPrice() external view returns (uint256);

    function isOverSpreadLimit()
        external
        view
        returns (
            bool result,
            uint256 marketPrice,
            uint256 oraclePrice
        );

    function isOverSpread(uint256 _limit)
        external
        view
        returns (
            bool result,
            uint256 marketPrice,
            uint256 oraclePrice
        );

    function getFundingPaymentEstimation(uint256 _cap)
        external
        view
        returns (
            bool notPayable,
            int256 premiumFractionLong,
            int256 premiumFractionShort,
            int256 fundingPayment,
            uint256 underlyingPrice
        );
}

