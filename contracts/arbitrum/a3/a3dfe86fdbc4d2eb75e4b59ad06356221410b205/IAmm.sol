// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import { IERC20 } from "./IERC20.sol";
import { Decimal } from "./Decimal.sol";
import { SignedDecimal } from "./SignedDecimal.sol";
import { ClearingHouse } from "./ClearingHouse.sol";

interface IAmm {
    /**
     * @notice asset direction, used in getInputPrice, getOutputPrice, swapInput and swapOutput
     * @param ADD_TO_AMM add asset to Amm
     * @param REMOVE_FROM_AMM remove asset from Amm
     */
    enum Dir {
        ADD_TO_AMM,
        REMOVE_FROM_AMM
    }

    struct Ratios {
        Decimal.decimal tollRatio;
        Decimal.decimal spreadRatio;
        Decimal.decimal initMarginRatio;
        Decimal.decimal maintenanceMarginRatio;
        Decimal.decimal partialLiquidationRatio;
        Decimal.decimal liquidationFeeRatio;
    }

    function swapInput(
        Dir _dir,
        Decimal.decimal calldata _quoteAssetAmount,
        Decimal.decimal calldata _baseAssetAmountLimit,
        bool _canOverFluctuationLimit
    ) external returns (Decimal.decimal memory);

    function swapOutput(
        Dir _dir,
        Decimal.decimal calldata _baseAssetAmount,
        Decimal.decimal calldata _quoteAssetAmountLimit
    ) external returns (Decimal.decimal memory);

    function settleFunding() external returns (SignedDecimal.signedDecimal memory);

    function calcFee(Decimal.decimal calldata _quoteAssetAmount, ClearingHouse.Side _side)
        external
        view
        returns (Decimal.decimal memory, Decimal.decimal memory);

    function repeg(
        Decimal.decimal memory _quoteAssetReserve,
        Decimal.decimal memory _baseAssetReserve
    ) external;

    //
    // VIEW
    //

    function getSpotPrice() external view returns (Decimal.decimal memory);

    function getUnderlyingPrice() external view returns (Decimal.decimal memory);

    function getReserves() external view returns (Decimal.decimal memory, Decimal.decimal memory);

    function getTollRatio() external view returns (Decimal.decimal memory);

    function getSpreadRatio() external view returns (Decimal.decimal memory);

    function getInitMarginRatio() external view returns (Decimal.decimal memory);

    function getMaintenanceMarginRatio() external view returns (Decimal.decimal memory);

    function getPartialLiquidationRatio() external view returns (Decimal.decimal memory);

    function getLiquidationFeeRatio() external view returns (Decimal.decimal memory);

    function getMaxHoldingBaseAsset() external view returns (Decimal.decimal memory);

    function getOpenInterestNotionalCap() external view returns (Decimal.decimal memory);

    function getBaseAssetDelta() external view returns (SignedDecimal.signedDecimal memory);

    function getCumulativeNotional() external view returns (SignedDecimal.signedDecimal memory);

    function x0() external view returns (Decimal.decimal memory);

    function y0() external view returns (Decimal.decimal memory);

    function fundingPeriod() external view returns (uint256);

    function quoteAsset() external view returns (IERC20);

    function open() external view returns (bool);

    function getRatios() external view returns (Ratios memory);

    function isOverFluctuationLimit(Dir _dirOfBase, Decimal.decimal memory _baseAssetAmount)
        external
        view
        returns (bool);

    function getInputTwap(Dir _dir, Decimal.decimal calldata _quoteAssetAmount)
        external
        view
        returns (Decimal.decimal memory);

    function getOutputTwap(Dir _dir, Decimal.decimal calldata _baseAssetAmount)
        external
        view
        returns (Decimal.decimal memory);

    function getInputPrice(Dir _dir, Decimal.decimal calldata _quoteAssetAmount)
        external
        view
        returns (Decimal.decimal memory);

    function getOutputPrice(Dir _dir, Decimal.decimal calldata _baseAssetAmount)
        external
        view
        returns (Decimal.decimal memory);

    function getInputPriceWithReserves(
        Dir _dir,
        Decimal.decimal memory _quoteAssetAmount,
        Decimal.decimal memory _quoteAssetPoolAmount,
        Decimal.decimal memory _baseAssetPoolAmount
    ) external pure returns (Decimal.decimal memory);

    function getOutputPriceWithReserves(
        Dir _dir,
        Decimal.decimal memory _baseAssetAmount,
        Decimal.decimal memory _quoteAssetPoolAmount,
        Decimal.decimal memory _baseAssetPoolAmount
    ) external pure returns (Decimal.decimal memory);
}

