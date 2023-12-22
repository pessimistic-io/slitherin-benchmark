//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import {IERC20Metadata} from "./extensions_IERC20Metadata.sol";
import {SafeCastUpgradeable} from "./SafeCastUpgradeable.sol";
import {SignedMathUpgradeable} from "./SignedMathUpgradeable.sol";
import {MathUpgradeable} from "./MathUpgradeable.sol";
import {IQuoter} from "./IQuoter.sol";
import {DataTypes} from "./libraries_DataTypes.sol";
import {ICauldron} from "./ICauldron.sol";
import {IPoolView} from "./IPoolView.sol";

import {CodecLib} from "./CodecLib.sol";
import {ContangoPositionNFT} from "./ContangoPositionNFT.sol";
import {IContangoQuoter} from "./IContangoQuoter.sol";

import "./libraries_DataTypes.sol";
import "./ErrorLib.sol";
import {SignedMathLib} from "./SignedMathLib.sol";
import {YieldUtils} from "./YieldUtils.sol";

import {ContangoYield} from "./ContangoYield.sol";

/// @title Contract for quoting position operations
contract ContangoYieldQuoter is IContangoQuoter {
    using SafeCastUpgradeable for uint256;
    using SafeCastUpgradeable for int256;
    using SignedMathUpgradeable for int256;
    using SignedMathLib for int256;
    using CodecLib for uint256;
    using YieldUtils for *;

    ContangoPositionNFT public immutable positionNFT;
    ContangoYield public immutable contangoYield;
    ICauldron public immutable cauldron;
    IQuoter public immutable quoter;
    IPoolView public immutable poolView;

    constructor(
        ContangoPositionNFT _positionNFT,
        ContangoYield _contangoYield,
        ICauldron _cauldron,
        IQuoter _quoter,
        IPoolView _poolView
    ) {
        positionNFT = _positionNFT;
        contangoYield = _contangoYield;
        cauldron = _cauldron;
        quoter = _quoter;
        poolView = _poolView;
    }

    /// @inheritdoc IContangoQuoter
    function positionStatus(PositionId positionId) external override returns (PositionStatus memory result) {
        (, Instrument memory instrument, YieldInstrument memory yieldInstrument) = _validateActivePosition(positionId);
        DataTypes.Balances memory balances = cauldron.balances(positionId.toVaultId());

        return _positionStatus(balances, instrument, yieldInstrument);
    }

    /// @inheritdoc IContangoQuoter
    function modifyCostForPosition(ModifyCostParams calldata params)
        external
        override
        returns (ModifyCostResult memory result)
    {
        (
            Position memory position,
            Instrument memory instrument,
            YieldInstrument memory yieldInstrument
        ) = _validateActivePosition(params.positionId);
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
        (Instrument memory instrument, YieldInstrument memory yieldInstrument) = contangoYield.yieldInstrument(
            params.symbol
        );

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
        (Position memory position, , YieldInstrument memory yieldInstrument) = _validateExpiredPosition(positionId);
        DataTypes.Balances memory balances = cauldron.balances(positionId.toVaultId());

        return cauldron.debtToBase(yieldInstrument.quoteId, balances.art) + position.protocolFees;
    }

    // ============================================== private functions ==============================================

    function _spot(Instrument memory instrument, int256 baseAmount) private returns (uint256) {
        if (baseAmount > 0) {
            return
                quoter.quoteExactInputSingle(
                    address(instrument.base),
                    address(instrument.quote),
                    instrument.uniswapFee,
                    uint256(baseAmount),
                    0
                );
        } else {
            return
                quoter.quoteExactOutputSingle(
                    address(instrument.quote),
                    address(instrument.base),
                    instrument.uniswapFee,
                    uint256(-baseAmount),
                    0
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

        (result.underlyingCollateral, ) = spotOracle.oracle.get(yieldInstrument.baseId, series.baseId, balances.ink);
        result.liquidationRatio = uint256(spotOracle.ratio);
    }

    function _modifyCostForLongPosition(
        DataTypes.Balances memory balances,
        Instrument memory instrument,
        YieldInstrument memory yieldInstrument,
        int256 quantity,
        int256 collateral
    ) internal returns (ModifyCostResult memory result) {
        if (quantity >= 0) {
            result = _increasingCostForLongPosition(
                balances,
                instrument,
                yieldInstrument,
                quantity.toUint256(),
                collateral
            );
        } else {
            result = _closingCostForLongPosition(balances, instrument, yieldInstrument, quantity.abs(), collateral);
        }
    }

    // **** NEW **** //
    function _increasingCostForLongPosition(
        DataTypes.Balances memory balances,
        Instrument memory instrument,
        YieldInstrument memory yieldInstrument,
        uint256 quantity,
        int256 collateral
    ) private returns (ModifyCostResult memory result) {
        uint256 hedge;
        int256 quoteQty;

        _assignLiquidity(yieldInstrument, result);

        if (quantity > 0) {
            if (result.basePoolLendingLiquidity < quantity) {
                result.needsForce = true;
                hedge = yieldInstrument.basePool.buyFYTokenPreview(result.basePoolLendingLiquidity);
                uint256 toMint = quantity - result.basePoolLendingLiquidity;
                hedge += toMint;
            } else {
                hedge = yieldInstrument.basePool.buyFYTokenPreview(quantity.toUint128());
            }

            quoteQty = -int256(_spot(instrument, -int256(hedge)));
            result.spotCost = -int256(_spot(instrument, -int256(quantity)));
        }

        DataTypes.Series memory series = cauldron.series(yieldInstrument.quoteId);
        DataTypes.SpotOracle memory spotOracle = cauldron.spotOracles(series.baseId, yieldInstrument.baseId);
        (result.underlyingCollateral, ) = spotOracle.oracle.get(
            yieldInstrument.baseId,
            series.baseId,
            balances.ink + quantity
        ); // ink * spot
        result.liquidationRatio = uint256(spotOracle.ratio);

        result.minDebt = yieldInstrument.minQuoteDebt;
        _calculateMinCollateral(balances, yieldInstrument, result, quoteQty);
        _calculateMaxCollateral(balances, yieldInstrument, result, quoteQty);
        _assignCollateralUsed(result, collateral);
        _calculateCost(balances, yieldInstrument, result, quoteQty, true);
    }

    /// @notice Quotes the bid rate, the base/quote are derived from the positionId
    // **** NEW **** //
    function _closingCostForLongPosition(
        DataTypes.Balances memory balances,
        Instrument memory instrument,
        YieldInstrument memory yieldInstrument,
        uint256 quantity,
        int256 collateral
    ) private returns (ModifyCostResult memory result) {
        _assignLiquidity(yieldInstrument, result);
        result.insufficientLiquidity = quantity > uint256(result.basePoolBorrowingLiquidity);

        if (!result.insufficientLiquidity) {
            uint256 amountRealBaseReceivedFromSellingLendingPosition = yieldInstrument.basePool.sellFYTokenPreview(
                quantity.toUint128()
            );

            result.spotCost = int256(_spot(instrument, int256(quantity)));
            int256 hedgeCost = int256(_spot(instrument, int256(amountRealBaseReceivedFromSellingLendingPosition)));

            DataTypes.Series memory series = cauldron.series(yieldInstrument.quoteId);
            DataTypes.SpotOracle memory spotOracle = cauldron.spotOracles(series.baseId, yieldInstrument.baseId);
            result.liquidationRatio = uint256(spotOracle.ratio);

            if (balances.ink == quantity) {
                uint256 costRecovered;
                uint128 maxFYTokenOut = poolView.maxFYTokenOut(yieldInstrument.quotePool);
                if (balances.art != 0) {
                    if (maxFYTokenOut < balances.art) {
                        result.needsForce = true;
                        costRecovered = maxFYTokenOut - yieldInstrument.quotePool.buyFYTokenPreview(maxFYTokenOut);
                    } else {
                        costRecovered = balances.art - yieldInstrument.quotePool.buyFYTokenPreview(balances.art);
                    }
                }
                result.cost = hedgeCost + int256(costRecovered);
            } else {
                (result.underlyingCollateral, ) = spotOracle.oracle.get(
                    yieldInstrument.baseId,
                    series.baseId,
                    balances.ink - quantity
                );
                result.minDebt = yieldInstrument.minQuoteDebt;
                _calculateMinCollateral(balances, yieldInstrument, result, hedgeCost);
                _calculateMaxCollateral(balances, yieldInstrument, result, hedgeCost);
                _assignCollateralUsed(result, collateral);
                _calculateCost(balances, yieldInstrument, result, hedgeCost, false);
            }
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
            uint256 refinancingRoomPV = instrument.quotePool.sellFYTokenPreview(maxDebtAfterModify - balances.art);
            result.minCollateral -= spotCost + int256(refinancingRoomPV);
        }

        if (balances.art > maxDebtAfterModify) {
            uint256 minDebtThatHasToBeBurnedPV = instrument.quotePool.buyFYTokenPreview(
                balances.art - maxDebtAfterModify
            );
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
            uint128 maxFYTokenOut = poolView.maxFYTokenOut(instrument.quotePool);
            uint128 maxDebtThatCanBeBurned = balances.art - result.minDebt;
            uint128 inputValue = maxFYTokenOut < maxDebtThatCanBeBurned ? maxFYTokenOut : maxDebtThatCanBeBurned;
            uint256 maxDebtThatCanBeBurnedPV = instrument.quotePool.buyFYTokenPreview(inputValue);

            // when minting 1:1
            if (maxDebtThatCanBeBurned > inputValue) {
                maxDebtThatCanBeBurnedPV += maxDebtThatCanBeBurned - inputValue;
            }

            result.maxCollateral = int256(maxDebtThatCanBeBurnedPV) - spotCost;
        }
    }

    function _minDebtPV(IPool pool, uint128 debt) internal view returns (uint128 debtPV) {
        uint256 tokenDecimals = IERC20Metadata(address(pool)).decimals();
        // Yield has a precision loss of up to 1e12, so for tokens with 18 decimals we use 12 decimals, for tokens with 6 decimals or less we use 0 as 10^0 == 1
        uint256 adjustmentDecimals = tokenDecimals - MathUpgradeable.min(6, tokenDecimals);

        debtPV = pool.sellFYTokenPreview(debt) + uint128(10**(adjustmentDecimals));
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
            if (quoteUsedToRepayDebt.abs() > uint256(result.quotePoolBorrowingLiquidity)) {
                result.insufficientLiquidity = true;
            } else {
                debtDelta128 = instrument.quotePool.buyBasePreview(quoteUsedToRepayDebt.abs().toUint128());
            }
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
        result.basePoolBorrowingLiquidity = poolView.maxFYTokenIn(instrument.basePool);
        result.basePoolLendingLiquidity = poolView.maxFYTokenOut(instrument.basePool);

        result.quotePoolBorrowingLiquidity = poolView.maxBaseOut(instrument.quotePool);
        result.quotePoolLendingLiquidity = poolView.maxBaseIn(instrument.quotePool);
    }

    function _assignCollateralUsed(ModifyCostResult memory result, int256 collateral) private pure {
        // if 'collateral' is above the max, use result.maxCollateral
        result.collateralUsed = SignedMathUpgradeable.min(collateral, result.maxCollateral);
        // if result.collateralUsed is lower than max, but still lower than the min, use the min
        result.collateralUsed = SignedMathUpgradeable.max(result.minCollateral, result.collateralUsed);
    }

    function _fee(
        PositionId positionId,
        Symbol symbol,
        uint256 cost
    ) private view returns (uint256) {
        address trader = PositionId.unwrap(positionId) == 0 ? msg.sender : positionNFT.positionOwner(positionId);
        return contangoYield.feeModel(symbol).calculateFee(trader, positionId, cost);
    }

    function _validatePosition(PositionId positionId)
        private
        view
        returns (
            Position memory position,
            Instrument memory instrument,
            YieldInstrument memory yieldInstrument
        )
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
        returns (
            Position memory position,
            Instrument memory instrument,
            YieldInstrument memory yieldInstrument
        )
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
        returns (
            Position memory position,
            Instrument memory instrument,
            YieldInstrument memory yieldInstrument
        )
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

