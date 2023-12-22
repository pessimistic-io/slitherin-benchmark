//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "./extensions_IERC20Metadata.sol";
import "./SafeCast.sol";
import "./SignedMath.sol";
import "./Math.sol";
import {IQuoter} from "./IQuoter.sol";
import {DataTypes} from "./libraries_DataTypes.sol";
import {ICauldron} from "./ICauldron.sol";

import {CodecLib} from "./CodecLib.sol";
import {ContangoPositionNFT} from "./ContangoPositionNFT.sol";
import {IContangoQuoter} from "./IContangoQuoter.sol";

import "./libraries_DataTypes.sol";
import "./ErrorLib.sol";
import {SignedMathLib} from "./SignedMathLib.sol";
import {MathLib} from "./MathLib.sol";
import {YieldUtils} from "./YieldUtils.sol";

import {ContangoYield} from "./ContangoYield.sol";

/// @title Contract for quoting position operations
contract ContangoYieldQuoter is IContangoQuoter {
    using SafeCast for uint256;
    using SafeCast for int256;
    using SignedMath for int256;
    using SignedMathLib for int256;
    using CodecLib for uint256;
    using MathLib for uint128;
    using YieldUtils for *;

    ContangoPositionNFT public immutable positionNFT;
    ContangoYield public immutable contangoYield;
    ICauldron public immutable cauldron;
    IQuoter public immutable quoter;

    constructor(ContangoPositionNFT _positionNFT, ContangoYield _contangoYield, ICauldron _cauldron, IQuoter _quoter) {
        positionNFT = _positionNFT;
        contangoYield = _contangoYield;
        cauldron = _cauldron;
        quoter = _quoter;
    }

    /// @inheritdoc IContangoQuoter
    function positionStatus(PositionId positionId) external override returns (PositionStatus memory result) {
        (, Instrument memory instrument, YieldInstrument memory yieldInstrument) = _validatePosition(positionId);
        DataTypes.Balances memory balances = cauldron.balances(positionId.toVaultId());

        return _positionStatus(balances, instrument, yieldInstrument);
    }

    /// @inheritdoc IContangoQuoter
    function modifyCostForPosition(ModifyCostParams calldata params)
        external
        override
        returns (ModifyCostResult memory result)
    {
        (Position memory position, Instrument memory instrument, YieldInstrument memory yieldInstrument) =
            _validateActivePosition(params.positionId);
        DataTypes.Balances memory balances = cauldron.balances(params.positionId.toVaultId());

        result = _modifyCostForLongPosition(balances, instrument, yieldInstrument, params.quantity, params.collateral);
        // TODO Egill review second condition
        if (result.needsBatchedCall || params.quantity == 0) {
            uint256 aggregateCost = (result.cost + result.financingCost).abs() + result.debtDelta.abs();
            result.fee = _fee(params.positionId, position.symbol, aggregateCost);
        } else {
            result.fee = _fee(params.positionId, position.symbol, result.cost.abs());
        }
    }

    /// @inheritdoc IContangoQuoter
    function openingCostForPosition(OpeningCostParams calldata params)
        external
        override
        returns (ModifyCostResult memory result)
    {
        (Instrument memory instrument, YieldInstrument memory yieldInstrument) =
            contangoYield.yieldInstrument(params.symbol);

        result = _modifyCostForLongPosition(
            DataTypes.Balances({art: 0, ink: 0}),
            instrument,
            yieldInstrument,
            int256(params.quantity),
            int256(params.collateral)
        );

        result.fee = _fee(PositionId.wrap(0), params.symbol, result.cost.abs());
    }

    /// @inheritdoc IContangoQuoter
    function deliveryCostForPosition(PositionId positionId) external override returns (uint256) {
        (Position memory position,, YieldInstrument memory yieldInstrument) = _validateExpiredPosition(positionId);
        DataTypes.Balances memory balances = cauldron.balances(positionId.toVaultId());

        return cauldron.debtToBase(yieldInstrument.quoteId, balances.art) + position.protocolFees;
    }

    // ============================================== private functions ==============================================

    function _spot(Instrument memory instrument, int256 baseAmount) private returns (uint256) {
        if (baseAmount > 0) {
            return quoter.quoteExactInputSingle(
                address(instrument.base), address(instrument.quote), instrument.uniswapFee, uint256(baseAmount), 0
            );
        } else {
            return quoter.quoteExactOutputSingle(
                address(instrument.quote), address(instrument.base), instrument.uniswapFee, uint256(-baseAmount), 0
            );
        }
    }

    function _positionStatus(
        DataTypes.Balances memory balances,
        Instrument memory instrument,
        YieldInstrument memory yieldInstrument
    ) private returns (PositionStatus memory result) {
        result.spotCost = _spot(instrument, int128(balances.ink));
        result.underlyingDebt = balances.art;

        DataTypes.Series memory series = cauldron.series(yieldInstrument.quoteId);
        DataTypes.SpotOracle memory spotOracle = cauldron.spotOracles(series.baseId, yieldInstrument.baseId);

        (result.underlyingCollateral,) = spotOracle.oracle.get(yieldInstrument.baseId, series.baseId, balances.ink);
        result.liquidationRatio = uint256(spotOracle.ratio);
    }

    function _modifyCostForLongPosition(
        DataTypes.Balances memory balances,
        Instrument memory instrument,
        YieldInstrument memory yieldInstrument,
        int256 quantity,
        int256 collateral
    ) internal returns (ModifyCostResult memory result) {
        result.minDebt = yieldInstrument.minQuoteDebt;
        DataTypes.Series memory series = cauldron.series(yieldInstrument.quoteId);
        DataTypes.Debt memory debt = cauldron.debt(series.baseId, yieldInstrument.baseId);
        result.maxAvailableDebt = uint128(debt.max * (10 ** debt.dec)) - debt.sum;
        _assignLiquidity(yieldInstrument, result);
        _evaluateLiquidity(yieldInstrument, balances, result, quantity, collateral);

        if (!result.insufficientLiquidity) {
            if (quantity >= 0) {
                _increasingCostForLongPosition(
                    result, balances, series, instrument, yieldInstrument, quantity.toUint256(), collateral
                );
            } else {
                _closingCostForLongPosition(
                    result, balances, series, instrument, yieldInstrument, quantity.abs(), collateral
                );
            }
        }
    }

    // **** NEW **** //
    function _increasingCostForLongPosition(
        ModifyCostResult memory result,
        DataTypes.Balances memory balances,
        DataTypes.Series memory series,
        Instrument memory instrument,
        YieldInstrument memory yieldInstrument,
        uint256 quantity,
        int256 collateral
    ) private {
        uint256 hedge;
        int256 quoteQty;

        if (quantity > 0) {
            if (result.basePoolLendingLiquidity < quantity) {
                result.needsForce = true;
                hedge = result.basePoolLendingLiquidity == 0
                    ? 0
                    : yieldInstrument.basePool.buyFYTokenPreview(result.basePoolLendingLiquidity);
                uint256 toMint = quantity - result.basePoolLendingLiquidity;
                hedge += toMint;
            } else {
                hedge = yieldInstrument.basePool.buyFYTokenPreview(quantity.toUint128());
            }

            quoteQty = -int256(_spot(instrument, -int256(hedge)));
            result.spotCost = -int256(_spot(instrument, -int256(quantity)));
        }

        DataTypes.SpotOracle memory spotOracle = cauldron.spotOracles(series.baseId, yieldInstrument.baseId);
        (result.underlyingCollateral,) =
            spotOracle.oracle.get(yieldInstrument.baseId, series.baseId, balances.ink + quantity); // ink * spot
        result.liquidationRatio = uint256(spotOracle.ratio);

        _calculateMinCollateral(balances, yieldInstrument, result, quoteQty);
        _calculateMaxCollateral(balances, yieldInstrument, result, quoteQty);
        _assignCollateralUsed(result, collateral);
        _calculateCost(balances, yieldInstrument, result, quoteQty, true);
    }

    /// @notice Quotes the bid rate, the base/quote are derived from the positionId
    // **** NEW **** //
    function _closingCostForLongPosition(
        ModifyCostResult memory result,
        DataTypes.Balances memory balances,
        DataTypes.Series memory series,
        Instrument memory instrument,
        YieldInstrument memory yieldInstrument,
        uint256 quantity,
        int256 collateral
    ) private {
        uint256 amountRealBaseReceivedFromSellingLendingPosition =
            yieldInstrument.basePool.sellFYTokenPreview(quantity.toUint128());

        result.spotCost = int256(_spot(instrument, int256(quantity)));
        int256 hedgeCost = int256(_spot(instrument, int256(amountRealBaseReceivedFromSellingLendingPosition)));

        DataTypes.SpotOracle memory spotOracle = cauldron.spotOracles(series.baseId, yieldInstrument.baseId);
        result.liquidationRatio = uint256(spotOracle.ratio);

        if (balances.ink == quantity) {
            uint256 costRecovered;
            uint256 maxFYTokenOut = yieldInstrument.quotePool.maxFYTokenOut.cap();
            if (balances.art != 0) {
                if (maxFYTokenOut < balances.art) {
                    result.needsForce = true;
                    costRecovered = maxFYTokenOut > 0
                        ? maxFYTokenOut - yieldInstrument.quotePool.buyFYTokenPreview(uint128(maxFYTokenOut))
                        : 0;
                } else {
                    costRecovered = balances.art - yieldInstrument.quotePool.buyFYTokenPreview(balances.art);
                }
            }
            result.cost = hedgeCost + int256(costRecovered);
        } else {
            (result.underlyingCollateral,) =
                spotOracle.oracle.get(yieldInstrument.baseId, series.baseId, balances.ink - quantity);
            _calculateMinCollateral(balances, yieldInstrument, result, hedgeCost);
            _calculateMaxCollateral(balances, yieldInstrument, result, hedgeCost);
            _assignCollateralUsed(result, collateral);
            _calculateCost(balances, yieldInstrument, result, hedgeCost, false);
        }
    }

    function _calculateMinCollateral(
        DataTypes.Balances memory balances,
        YieldInstrument memory instrument,
        ModifyCostResult memory result,
        int256 spotCost
    ) private view {
        uint128 maxDebtAfterModify = ((result.underlyingCollateral * 1e6) / result.liquidationRatio).toUint128();

        if (balances.art < maxDebtAfterModify) {
            uint128 diff = maxDebtAfterModify - balances.art;
            uint128 maxBorrowableAmount = uint128(Math.min(result.quotePoolBorrowingLiquidity, result.maxAvailableDebt));
            uint256 refinancingRoomPV =
                instrument.quotePool.sellFYTokenPreview(diff > maxBorrowableAmount ? maxBorrowableAmount : diff);
            result.minCollateral -= spotCost + int256(refinancingRoomPV);
        }

        if (balances.art > maxDebtAfterModify) {
            uint128 diff = balances.art - maxDebtAfterModify;
            uint128 liquidity = instrument.quotePool.maxFYTokenOut.cap();
            uint256 minDebtThatHasToBeBurnedPV = diff > liquidity
                ? instrument.quotePool.buyFYTokenPreview(liquidity) + (diff - liquidity)
                : instrument.quotePool.buyFYTokenPreview(diff);

            result.minCollateral = int256(minDebtThatHasToBeBurnedPV) - spotCost;
        }
    }

    function _calculateMaxCollateral(
        DataTypes.Balances memory balances,
        YieldInstrument memory instrument,
        ModifyCostResult memory result,
        int256 spotCost
    ) private view {
        // this covers the case where there is no existing debt, which applies to new positions or fully liquidated positions
        if (balances.art == 0) {
            uint256 minDebtPV = _minDebtPV(instrument.quotePool, result.minDebt);
            result.maxCollateral = spotCost.absi() - int256(minDebtPV);
        } else {
            uint128 maxFYTokenOut = instrument.quotePool.maxFYTokenOut.cap();
            uint128 maxDebtThatCanBeBurned = balances.art - result.minDebt;
            uint256 maxDebtThatCanBeBurnedPV;
            if (maxDebtThatCanBeBurned > 0) {
                uint128 inputValue = maxFYTokenOut < maxDebtThatCanBeBurned ? maxFYTokenOut : maxDebtThatCanBeBurned;
                maxDebtThatCanBeBurnedPV = instrument.quotePool.buyFYTokenPreview(inputValue);

                // when minting 1:1
                if (maxDebtThatCanBeBurned > inputValue) {
                    maxDebtThatCanBeBurnedPV += maxDebtThatCanBeBurned - inputValue;
                }
            }
            result.maxCollateral = int256(maxDebtThatCanBeBurnedPV) - spotCost;
        }
    }

    function _minDebtPV(IPool pool, uint128 debt) internal view returns (uint128 debtPV) {
        uint256 tokenDecimals = IERC20Metadata(address(pool)).decimals();
        // Yield has a precision loss of up to 1e12, so for tokens with 18 decimals we use 12 decimals, for tokens with 6 decimals or less we use 0 as 10^0 == 1
        uint256 adjustmentDecimals = tokenDecimals - Math.min(6, tokenDecimals);

        debtPV = pool.sellFYTokenPreview(debt) + uint128(10 ** (adjustmentDecimals));
    }

    // NEEDS BATCHED CALL
    // * decrease and withdraw more than we get from spot
    // * decrease and post at the same time SUPPORTED
    // * increase and withdraw at the same time ???
    // * increase and post more than what we need to pay the spot

    function _calculateCost(
        DataTypes.Balances memory balances,
        YieldInstrument memory instrument,
        ModifyCostResult memory result,
        int256 spotCost,
        bool isIncrease
    ) private view {
        int256 quoteUsedToRepayDebt = result.collateralUsed + spotCost;
        result.underlyingDebt = balances.art;
        uint128 debtDelta128;

        if (quoteUsedToRepayDebt > 0) {
            uint128 baseToSell = uint128(uint256(quoteUsedToRepayDebt));
            if (result.quotePoolLendingLiquidity < baseToSell) {
                result.needsForce = true;
                debtDelta128 = instrument.quotePool.sellBasePreview(result.quotePoolLendingLiquidity);
                // remainder is paid by minting 1:1
                debtDelta128 += baseToSell - result.quotePoolLendingLiquidity;
            } else {
                debtDelta128 = instrument.quotePool.sellBasePreview(baseToSell);
            }
            result.debtDelta = -int256(uint256(debtDelta128));
            result.underlyingDebt -= debtDelta128;
            if (isIncrease) {
                // this means we're increasing, and posting more than what we need to pay the spot
                result.needsBatchedCall = true;
            }
        }
        if (quoteUsedToRepayDebt < 0) {
            debtDelta128 = instrument.quotePool.buyBasePreview(quoteUsedToRepayDebt.abs().toUint128());
            result.debtDelta = int256(uint256(debtDelta128));
            result.underlyingDebt += debtDelta128;
            if (!isIncrease) {
                // this means that we're decreasing, and withdrawing more than we get from the spot
                result.needsBatchedCall = true;
            }
        }
        result.financingCost = result.debtDelta + quoteUsedToRepayDebt;
        result.cost -= result.collateralUsed + result.debtDelta;
    }

    function _assignLiquidity(YieldInstrument memory instrument, ModifyCostResult memory result) private view {
        result.basePoolBorrowingLiquidity = instrument.basePool.maxFYTokenIn.cap();
        result.basePoolLendingLiquidity = instrument.basePool.maxFYTokenOut.cap();

        result.quotePoolBorrowingLiquidity = instrument.quotePool.maxFYTokenIn.cap();
        result.quotePoolLendingLiquidity = instrument.quotePool.maxBaseIn.cap();
    }

    function _evaluateLiquidity(
        YieldInstrument memory instrument,
        DataTypes.Balances memory balances,
        ModifyCostResult memory result,
        int256 quantity,
        int256 collateral
    ) internal view {
        // If we're opening a new position
        if (balances.art == 0 && quantity > 0) {
            result.insufficientLiquidity =
                Math.min(result.quotePoolBorrowingLiquidity, result.maxAvailableDebt) < result.minDebt;
        }

        // If we're withdrawing from a position
        if (quantity == 0 && collateral < 0) {
            result.insufficientLiquidity = instrument.quotePool.maxBaseOut.cap() < collateral.abs();
        }

        // If we're reducing a position
        if (quantity < 0) {
            result.insufficientLiquidity = result.basePoolBorrowingLiquidity < quantity.abs();
        }
    }

    function _assignCollateralUsed(ModifyCostResult memory result, int256 collateral) private pure {
        // if 'collateral' is above the max, use result.maxCollateral
        result.collateralUsed = SignedMath.min(collateral, result.maxCollateral);
        // if result.collateralUsed is lower than max, but still lower than the min, use the min
        result.collateralUsed = SignedMath.max(result.minCollateral, result.collateralUsed);
    }

    function _fee(PositionId positionId, Symbol symbol, uint256 cost) private view returns (uint256) {
        address trader = PositionId.unwrap(positionId) == 0 ? msg.sender : positionNFT.positionOwner(positionId);
        return contangoYield.feeModel(symbol).calculateFee(trader, positionId, cost);
    }

    function _validatePosition(PositionId positionId)
        private
        view
        returns (Position memory position, Instrument memory instrument, YieldInstrument memory yieldInstrument)
    {
        position = contangoYield.position(positionId);
        if (position.openQuantity == 0 && position.openCost == 0) {
            if (position.collateral <= 0) {
                revert InvalidPosition(positionId);
            }
        }
        (instrument, yieldInstrument) = contangoYield.yieldInstrument(position.symbol);
    }

    function _validateActivePosition(PositionId positionId)
        private
        view
        returns (Position memory position, Instrument memory instrument, YieldInstrument memory yieldInstrument)
    {
        (position, instrument, yieldInstrument) = _validatePosition(positionId);

        // solhint-disable-next-line not-rely-on-time
        uint256 timestamp = block.timestamp;
        if (instrument.maturity <= timestamp) {
            revert PositionExpired(positionId, instrument.maturity, timestamp);
        }
    }

    function _validateExpiredPosition(PositionId positionId)
        private
        view
        returns (Position memory position, Instrument memory instrument, YieldInstrument memory yieldInstrument)
    {
        (position, instrument, yieldInstrument) = _validatePosition(positionId);

        // solhint-disable-next-line not-rely-on-time
        uint256 timestamp = block.timestamp;
        if (instrument.maturity > timestamp) {
            revert PositionActive(positionId, instrument.maturity, timestamp);
        }
    }

    receive() external payable {
        revert ViewOnly();
    }

    /// @notice reverts on fallback for informational purposes
    fallback() external payable {
        revert FunctionNotFound(msg.sig);
    }
}

