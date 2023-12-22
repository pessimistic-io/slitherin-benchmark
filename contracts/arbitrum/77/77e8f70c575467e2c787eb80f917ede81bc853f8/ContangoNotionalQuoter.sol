//SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./IContangoQuoter.sol";

import "./QuoterLib.sol";

import "./ContangoNotional.sol";

// solhint-disable not-rely-on-time
contract ContangoNotionalQuoter is IContangoQuoter {
    using NotionalUtils for *;
    using ProxyLib for PositionId;
    using QuoterLib for IQuoter;
    using SafeCast for *;
    using SignedMath for int256;

    // TODO alfredo - this will probably have a lot in common with ContangoYieldQuoter.sol, check if code can be shared

    // TODO alfredo - look into optimising max usable liquidity via binary searching

    ContangoPositionNFT public immutable positionNFT;
    ContangoNotional public immutable contangoNotional;
    IQuoter public immutable quoter;
    NotionalProxy public immutable notional;

    struct CollateralAndLeverage {
        int256 collateral;
        int256 collateralSlippage;
        uint256 leverage;
    }

    struct InstrumentData {
        InstrumentStorage instrument;
        NotionalInstrumentStorage notionalInstrument;
        ContangoVault vault;
    }

    constructor(
        ContangoPositionNFT _positionNFT,
        ContangoNotional _contangoNotional,
        IQuoter _quoter,
        NotionalProxy _notional
    ) {
        positionNFT = _positionNFT;
        contangoNotional = _contangoNotional;
        quoter = _quoter;
        notional = _notional;
    }

    /// @inheritdoc IContangoQuoter
    function positionStatus(PositionId positionId, uint24 uniswapFee)
        external
        override
        returns (PositionStatus memory)
    {
        (, InstrumentData memory instrumentData) = _validateActivePosition(positionId);

        return _positionStatus(positionId, instrumentData, uniswapFee);
    }

    /// @inheritdoc IContangoQuoter
    function openingCostForPositionWithLeverage(OpeningCostParams calldata params, uint256 leverage)
        external
        override
        returns (ModifyCostResult memory result)
    {
        result = _openingCostForPosition(params, 0, leverage);
    }

    /// @inheritdoc IContangoQuoter
    function openingCostForPositionWithCollateral(OpeningCostParams calldata params, uint256 collateral)
        external
        override
        returns (ModifyCostResult memory result)
    {
        result = _openingCostForPosition(params, collateral, 0);
    }

    /// @inheritdoc IContangoQuoter
    function modifyCostForPositionWithLeverage(ModifyCostParams calldata params, uint256 leverage)
        external
        override
        returns (ModifyCostResult memory result)
    {
        result = _modifyCostForPosition(params, 0, leverage);
    }

    /// @inheritdoc IContangoQuoter
    function modifyCostForPositionWithCollateral(ModifyCostParams calldata params, int256 collateral)
        external
        override
        returns (ModifyCostResult memory result)
    {
        result = _modifyCostForPosition(params, collateral, 0);
    }

    /// @inheritdoc IContangoQuoter
    function deliveryCostForPosition(PositionId positionId)
        external
        view
        override
        returns (DeliveryCostResult memory result)
    {
        (Position memory position, InstrumentData memory instrumentData) = _validateExpiredPosition(positionId);
        VaultAccount memory vaultAccount = _getVaultAccount(positionId, instrumentData.vault);

        result = _deliveryCostForPosition(positionId, vaultAccount, instrumentData.notionalInstrument, position);
    }

    // ============================================== Private functions ==============================================

    function _openingCostForPosition(OpeningCostParams calldata params, uint256 collateral, uint256 leverage)
        private
        returns (ModifyCostResult memory result)
    {
        InstrumentData memory instrumentData = _instrument(params.symbol);

        _checkClosingOnly(params.symbol, instrumentData.instrument);

        VaultAccount memory vaultAccount; // empty account since it's a new position
        result = _modifyCostForPosition(
            instrumentData,
            vaultAccount,
            params.quantity.toInt256(),
            collateral.toInt256(),
            params.collateralSlippage,
            leverage,
            params.uniswapFee
        );

        result.fee = QuoterLib.fee(contangoNotional, positionNFT, PositionId.wrap(0), params.symbol, result.cost.abs());
    }

    function _modifyCostForPosition(ModifyCostParams calldata params, int256 collateral, uint256 leverage)
        private
        returns (ModifyCostResult memory result)
    {
        (Position memory position, InstrumentData memory instrumentData) = _validateActivePosition(params.positionId);
        VaultAccount memory vaultAccount = _getVaultAccount(params.positionId, instrumentData.vault);

        if (params.quantity > 0) {
            _checkClosingOnly(position.symbol, instrumentData.instrument);
        }

        result = _modifyCostForPosition(
            instrumentData,
            vaultAccount,
            params.quantity,
            collateral,
            params.collateralSlippage,
            leverage,
            params.uniswapFee
        );
        if (result.needsBatchedCall || params.quantity == 0) {
            uint256 aggregateCost = (result.cost + result.financingCost).abs() + result.debtDelta.abs();
            result.fee = QuoterLib.fee(contangoNotional, positionNFT, params.positionId, position.symbol, aggregateCost);
        } else {
            result.fee =
                QuoterLib.fee(contangoNotional, positionNFT, params.positionId, position.symbol, result.cost.abs());
        }
    }

    function _checkClosingOnly(Symbol symbol, InstrumentStorage memory instrument) private view {
        if (contangoNotional.closingOnly()) {
            revert ClosingOnly();
        }
        if (instrument.closingOnly) {
            revert InstrumentClosingOnly(symbol);
        }
    }

    function _modifyCostForPosition(
        InstrumentData memory instrumentData,
        VaultAccount memory vaultAccount,
        int256 quantity,
        int256 collateral,
        uint256 collateralSlippage,
        uint256 leverage,
        uint24 uniswapFee
    ) internal returns (ModifyCostResult memory result) {
        VaultConfig memory vaultConfig = notional.getVaultConfig(address(instrumentData.vault));
        result.liquidationRatio = _liquidationRatio(vaultConfig);

        CollateralAndLeverage memory collateralAndLeverage =
            CollateralAndLeverage(collateral, 1e18 + collateralSlippage.toInt256(), leverage);

        // TODO alfredo - set proper liquidity
        result.baseLendingLiquidity = type(uint256).max;
        result.quoteLendingLiquidity = type(uint256).max;

        if (quantity >= 0) {
            // TODO alfredo - this will adjust the quantity for calculations but we're not telling we did it back to the result
            uint256 uQuantity =
                quantity.toUint256().roundFloorNotionalPrecision(instrumentData.notionalInstrument.basePrecision);
            _increasingCostForPosition(
                result, instrumentData, vaultAccount, vaultConfig, uQuantity, collateralAndLeverage, uniswapFee
            );
        } else {
            // TODO alfredo - this will adjust the quantity for calculations but we're not telling we did it back to the result
            uint256 uQuantity =
                (-quantity).toUint256().roundFloorNotionalPrecision(instrumentData.notionalInstrument.basePrecision);
            _decreasingCostForPosition(
                result, instrumentData, vaultAccount, vaultConfig, uQuantity, collateralAndLeverage, uniswapFee
            );
        }
    }

    function _minDebt(
        NotionalInstrumentStorage memory notionalInstrument,
        VaultConfig memory vaultConfig,
        uint256 underlyingCollateral
    ) private pure returns (uint256 fCashMinDebt, uint128 minDebt) {
        // cap min debt required by taking max collateral ratio into account
        int256 requiredDebt =
            (underlyingCollateral.toInt256() * Constants.RATE_PRECISION) / vaultConfig.maxRequiredAccountCollateralRatio;

        fCashMinDebt = Math.max(
            requiredDebt.toUint256().toNotionalPrecision(notionalInstrument.quotePrecision, true),
            vaultConfig.minAccountBorrowSize.toUint256()
        );
        minDebt = fCashMinDebt.fromNotionalPrecision(notionalInstrument.quotePrecision, true).toUint128();
    }

    function _increasingCostForPosition(
        ModifyCostResult memory result,
        InstrumentData memory instrumentData,
        VaultAccount memory vaultAccount,
        VaultConfig memory vaultConfig,
        uint256 quantity,
        CollateralAndLeverage memory collateralAndLeverage,
        uint24 uniswapFee
    ) private {
        uint256 fCashQuantity;
        uint256 fCashMinDebt;
        (fCashQuantity, result.underlyingCollateral, fCashMinDebt, result.minDebt) =
            _calculateMinDebtForIncrease(instrumentData, vaultAccount, vaultConfig, quantity);

        _evaluateIncreaseLiquidity(
            instrumentData.instrument, instrumentData.notionalInstrument, vaultAccount, fCashMinDebt
        );

        uint256 hedge;
        int256 hedgeCost;

        if (quantity > 0) {
            hedge =
                notional.quoteLendOpenCost(fCashQuantity, instrumentData.instrument, instrumentData.notionalInstrument);
            if (hedge == 0) {
                // no liquidity
                result.quoteLendingLiquidity = 0;
                hedge = quantity;
            }

            hedgeCost = -int256(
                quoter.spot(
                    address(instrumentData.instrument.base),
                    address(instrumentData.instrument.quote),
                    -int256(hedge),
                    uniswapFee
                )
            );
            result.spotCost = -int256(
                quoter.spot(
                    address(instrumentData.instrument.base),
                    address(instrumentData.instrument.quote),
                    -int256(quantity),
                    uniswapFee
                )
            );
        }

        _calculateMinCollateral(
            result,
            instrumentData.instrument,
            instrumentData.notionalInstrument,
            vaultAccount,
            hedgeCost,
            fCashMinDebt,
            collateralAndLeverage.collateralSlippage
        );
        _calculateMaxCollateral(
            result,
            instrumentData.instrument,
            instrumentData.notionalInstrument,
            vaultAccount,
            hedgeCost,
            fCashMinDebt,
            collateralAndLeverage.collateralSlippage
        );
        _assignCollateralUsed(
            instrumentData.instrument,
            instrumentData.notionalInstrument,
            vaultAccount,
            result,
            collateralAndLeverage,
            hedgeCost
        );
        _calculateCost(
            result, instrumentData.instrument, instrumentData.notionalInstrument, vaultAccount, hedgeCost, true
        );
    }

    function _calculateMinDebtForIncrease(
        InstrumentData memory instrumentData,
        VaultAccount memory vaultAccount,
        VaultConfig memory vaultConfig,
        uint256 quantity
    )
        private
        view
        returns (uint256 fCashQuantity, uint256 underlyingCollateral, uint256 fCashMinDebt, uint128 minDebt)
    {
        fCashQuantity = quantity.toNotionalPrecision(instrumentData.notionalInstrument.basePrecision, true);
        underlyingCollateral = _underlyingCollateral(
            instrumentData.vault, fCashQuantity + vaultAccount.vaultShares, instrumentData.instrument.maturity
        );
        (fCashMinDebt, minDebt) = _minDebt(instrumentData.notionalInstrument, vaultConfig, underlyingCollateral);
    }

    function _evaluateIncreaseLiquidity(
        InstrumentStorage memory instrument,
        NotionalInstrumentStorage memory notionalInstrument,
        VaultAccount memory vaultAccount,
        uint256 fCashMinDebt
    ) private view {
        uint256 currentDebt = vaultAccount.fCash.abs();
        // currentDebt should be either 0 or >= minDebt
        if (
            currentDebt < fCashMinDebt
                && notional.quoteBorrowOpen(fCashMinDebt - currentDebt, instrument, notionalInstrument) == 0
        ) {
            revert InsufficientLiquidity();
        }
    }

    function _decreasingCostForPosition(
        ModifyCostResult memory result,
        InstrumentData memory instrumentData,
        VaultAccount memory vaultAccount,
        VaultConfig memory vaultConfig,
        uint256 quantity,
        CollateralAndLeverage memory collateralAndLeverage,
        uint24 uniswapFee
    ) private {
        uint256 fCashQuantity;
        uint256 fCashMinDebt;
        (fCashQuantity, result.underlyingCollateral, fCashMinDebt, result.minDebt) =
            _calculateMinDebtForDecrease(instrumentData, vaultAccount, vaultConfig, quantity);

        uint256 amountRealBaseReceivedFromSellingLendingPosition =
            notional.quoteLendClose(fCashQuantity, instrumentData.instrument, instrumentData.notionalInstrument);

        if (amountRealBaseReceivedFromSellingLendingPosition == 0) {
            revert InsufficientLiquidity();
        }

        result.spotCost = int256(
            quoter.spot(
                address(instrumentData.instrument.base),
                address(instrumentData.instrument.quote),
                int256(quantity),
                uniswapFee
            )
        );
        int256 hedgeCost = int256(
            quoter.spot(
                address(instrumentData.instrument.base),
                address(instrumentData.instrument.quote),
                int256(amountRealBaseReceivedFromSellingLendingPosition),
                uniswapFee
            )
        );

        // goes around possible rounding issues
        if (
            vaultAccount.vaultShares.fromNotionalPrecision(instrumentData.notionalInstrument.basePrecision, false)
                == quantity
        ) {
            _fullyCloseCost(
                result, instrumentData.instrument, instrumentData.notionalInstrument, vaultAccount, hedgeCost
            );
        } else {
            _calculateMinCollateral(
                result,
                instrumentData.instrument,
                instrumentData.notionalInstrument,
                vaultAccount,
                hedgeCost,
                fCashMinDebt,
                collateralAndLeverage.collateralSlippage
            );
            _calculateMaxCollateral(
                result,
                instrumentData.instrument,
                instrumentData.notionalInstrument,
                vaultAccount,
                hedgeCost,
                fCashMinDebt,
                collateralAndLeverage.collateralSlippage
            );
            _assignCollateralUsed(
                instrumentData.instrument,
                instrumentData.notionalInstrument,
                vaultAccount,
                result,
                collateralAndLeverage,
                hedgeCost
            );
            _calculateCost(
                result, instrumentData.instrument, instrumentData.notionalInstrument, vaultAccount, hedgeCost, false
            );
        }
    }

    function _fullyCloseCost(
        ModifyCostResult memory result,
        InstrumentStorage memory instrument,
        NotionalInstrumentStorage memory notionalInstrument,
        VaultAccount memory vaultAccount,
        int256 hedgeCost
    ) private view {
        uint256 debt = vaultAccount.fCash.abs();
        uint256 borrowCloseCost = notional.quoteBorrowCloseCost(debt, instrument, notionalInstrument);
        if (borrowCloseCost == 0) {
            // TODO alfredo - need to find out how do we cancel de debt 1:1, otherwise this won't be possible
            revert NotImplemented(
                "_decreasingCostForPosition() - lack of quote lending liquidity - needs 1:1 debt repayment"
            );
        }

        uint256 costRecovered = debt.fromNotionalPrecision(notionalInstrument.quotePrecision, false) - borrowCloseCost;
        result.cost = hedgeCost + int256(costRecovered);
    }

    function _calculateMinDebtForDecrease(
        InstrumentData memory instrumentData,
        VaultAccount memory vaultAccount,
        VaultConfig memory vaultConfig,
        uint256 quantity
    )
        private
        view
        returns (uint256 fCashQuantity, uint256 underlyingCollateral, uint256 fCashMinDebt, uint128 minDebt)
    {
        fCashQuantity = quantity.toNotionalPrecision(instrumentData.notionalInstrument.basePrecision, true);
        underlyingCollateral = _underlyingCollateral(
            instrumentData.vault, vaultAccount.vaultShares - fCashQuantity, instrumentData.instrument.maturity
        );
        (fCashMinDebt, minDebt) = _minDebt(instrumentData.notionalInstrument, vaultConfig, underlyingCollateral);
    }

    function _positionStatus(PositionId positionId, InstrumentData memory instrumentData, uint24 uniswapFee)
        private
        returns (PositionStatus memory result)
    {
        VaultAccount memory vaultAccount = _getVaultAccount(positionId, instrumentData.vault);

        result.spotCost = quoter.spot(
            address(instrumentData.instrument.base),
            address(instrumentData.instrument.quote),
            int256(
                vaultAccount.vaultShares.fromNotionalPrecision(instrumentData.notionalInstrument.basePrecision, true)
            ),
            uniswapFee
        );
        result.underlyingDebt =
            uint256(-vaultAccount.fCash).fromNotionalPrecision(instrumentData.notionalInstrument.quotePrecision, true);
        result.underlyingCollateral =
            _underlyingCollateral(instrumentData.vault, vaultAccount.vaultShares, instrumentData.instrument.maturity);
        result.liquidationRatio = _liquidationRatio(notional.getVaultConfig(address(instrumentData.vault)));
    }

    function _getVaultAccount(PositionId positionId, ContangoVault vault) private view returns (VaultAccount memory) {
        address proxy = positionId.computeProxyAddress(address(contangoNotional), contangoNotional.proxyHash());
        return notional.getVaultAccount(proxy, address(vault));
    }

    function _underlyingCollateral(ContangoVault vault, uint256 fCash, uint256 maturity)
        private
        view
        returns (uint256)
    {
        return uint256(vault.convertStrategyToUnderlying(address(0), fCash, maturity));
    }

    function _liquidationRatio(VaultConfig memory vaultConfig) private pure returns (uint256) {
        // Notional stores minCollateralRatio as 1e9 (Constants.RATE_PRECISION) and assumes it's always over collateralised, so min 100%
        // e.g. 140% liquidation ratio is stored on Notional as 0.4e9 and we parse it to 1.4e6 for internal use
        return 1e6 + (uint256(vaultConfig.minCollateralRatio) / 1e3);
    }

    function _calculateMinCollateral(
        ModifyCostResult memory result,
        InstrumentStorage memory instrument,
        NotionalInstrumentStorage memory notionalInstrument,
        VaultAccount memory vaultAccount,
        int256 hedgeCost,
        uint256 fCashMinDebt,
        int256 collateralSlippage
    ) private view {
        uint256 maxDebtAfterModify = ((result.underlyingCollateral * 1e6) / result.liquidationRatio).toNotionalPrecision(
            notionalInstrument.quotePrecision, false
        );

        uint256 currentDebt = vaultAccount.fCash.abs();
        if (currentDebt < maxDebtAfterModify) {
            // TODO alfredo - liquidation: how is debt valued? if not FV = PV then this doesn't work
            uint256 remainingAvailableDebt = maxDebtAfterModify - currentDebt;
            uint256 refinancingRoomPV = notional.quoteBorrowOpen(remainingAvailableDebt, instrument, notionalInstrument);
            if (refinancingRoomPV == 0) {
                // not enough liquidity but up to min debt is guaranteed due to earlier checks
                remainingAvailableDebt = currentDebt >= fCashMinDebt ? 0 : fCashMinDebt - currentDebt;
                refinancingRoomPV =
                    remainingAvailableDebt.fromNotionalPrecision(notionalInstrument.quotePrecision, true);
            }

            result.minCollateral -= hedgeCost + int256(refinancingRoomPV);
        }

        if (currentDebt > maxDebtAfterModify) {
            uint256 diff = vaultAccount.fCash.abs() - maxDebtAfterModify;
            uint256 closeCost = notional.quoteBorrowCloseCost(diff, instrument, notionalInstrument);
            if (closeCost == 0) {
                // TODO alfredo - need to find out how do we cancel de debt 1:1, otherwise this won't be possible
                revert NotImplemented(
                    "_calculateMinCollateral() - lack of quote lending liquidity - needs 1:1 debt repayment"
                );
            }

            result.minCollateral = int256(closeCost) - hedgeCost;
        }

        if (collateralSlippage != 1e18) {
            result.minCollateral = result.minCollateral > 0
                ? SignedMath.min((result.minCollateral * collateralSlippage) / 1e18, -hedgeCost)
                : (result.minCollateral * 1e18) / collateralSlippage;
        }
    }

    function _calculateMaxCollateral(
        ModifyCostResult memory result,
        InstrumentStorage memory instrument,
        NotionalInstrumentStorage memory notionalInstrument,
        VaultAccount memory vaultAccount,
        int256 hedgeCost,
        uint256 fCashMinDebt,
        int256 collateralSlippage
    ) private view {
        // this covers the case where there is no existing debt, which applies to new positions or fully liquidated positions
        if (vaultAccount.fCash == 0) {
            // if there's no liquidity to borrow, will return zero and be the same as requesting to mint it all 1:1
            uint256 minDebtPV = notional.quoteBorrowOpen(fCashMinDebt, instrument, notionalInstrument);
            result.maxCollateral = int256(hedgeCost.abs() - minDebtPV);
        } else {
            int256 delta;
            uint256 fCash = vaultAccount.fCash.abs();

            if (fCash > fCashMinDebt) {
                uint256 maxDebtThatCanBeBurned = fCash - fCashMinDebt;
                delta = notional.quoteBorrowCloseCost(maxDebtThatCanBeBurned, instrument, notionalInstrument).toInt256();
                if (delta == 0) {
                    // TODO alfredo - need to find out how do we cancel de debt 1:1, otherwise this won't be possible
                    revert NotImplemented(
                        "_calculateMaxCollateral() - lack of quote lending liquidity - needs 1:1 debt repayment"
                    );
                }
            } else if (fCash < fCashMinDebt) {
                uint256 minDebtNeeded = fCashMinDebt - fCash;
                delta = -notional.quoteBorrowOpen(minDebtNeeded, instrument, notionalInstrument).toInt256();
                if (delta == 0) {
                    // if there's no liquidity to borrow, mint it all 1:1
                    delta = -minDebtNeeded.toInt256();
                }
            }
            result.maxCollateral = delta - hedgeCost;
        }

        if (collateralSlippage != 1e18) {
            result.maxCollateral = result.maxCollateral < 0
                ? (result.maxCollateral * collateralSlippage) / 1e18
                : (result.maxCollateral * collateralSlippage) / collateralSlippage;
        }
    }

    function _assignCollateralUsed(
        InstrumentStorage memory instrument,
        NotionalInstrumentStorage memory notionalInstrument,
        VaultAccount memory vaultAccount,
        ModifyCostResult memory result,
        CollateralAndLeverage memory collateralAndLeverage,
        int256 hedgeCost
    ) private view {
        int256 collateral = collateralAndLeverage.leverage > 0
            ? _deriveCollateralFromLeverage(
                instrument, notionalInstrument, vaultAccount, result, collateralAndLeverage.leverage, hedgeCost
            )
            : collateralAndLeverage.collateral;

        // if 'collateral' is above the max, use result.maxCollateral
        result.collateralUsed = SignedMath.min(collateral, result.maxCollateral);
        // if result.collateralUsed is lower than max, but still lower than the min, use the min
        result.collateralUsed = SignedMath.max(result.minCollateral, result.collateralUsed);
    }

    // leverage = 1 / ((underlyingCollateral - underlyingDebt) / underlyingCollateral)
    // leverage = underlyingCollateral / (underlyingCollateral - underlyingDebt)
    // underlyingDebt = -underlyingCollateral / leverage + underlyingCollateral
    // collateral = hedgeCost - underlyingDebtPV
    function _deriveCollateralFromLeverage(
        InstrumentStorage memory instrument,
        NotionalInstrumentStorage memory notionalInstrument,
        VaultAccount memory vaultAccount,
        ModifyCostResult memory result,
        uint256 leverage,
        int256 hedgeCost
    ) internal view returns (int256 collateral) {
        uint256 debtFV = (
            ((-int256(result.underlyingCollateral) * 1e18) / int256(leverage)) + int256(result.underlyingCollateral)
        ).toUint256().toNotionalPrecision(notionalInstrument.quotePrecision, false);

        uint256 currentDebt = vaultAccount.fCash.abs();
        int256 debtPV;
        if (debtFV > currentDebt) {
            // Debt needs to increase to reach the desired leverage
            debtPV = int256(notional.quoteBorrowOpen(debtFV - currentDebt, instrument, notionalInstrument));
        } else {
            // Debt needs to be burnt to reach the desired leverage
            debtPV = -int256(notional.quoteBorrowCloseCost(currentDebt - debtFV, instrument, notionalInstrument));
        }

        collateral = hedgeCost.abs().toInt256() - debtPV;
    }

    function _calculateCost(
        ModifyCostResult memory result,
        InstrumentStorage memory instrument,
        NotionalInstrumentStorage memory notionalInstrument,
        VaultAccount memory vaultAccount,
        int256 hedgeCost,
        bool isIncrease
    ) private view {
        int256 quoteUsedToRepayDebt = result.collateralUsed + hedgeCost;
        result.underlyingDebt = vaultAccount.fCash.abs().fromNotionalPrecision(notionalInstrument.quotePrecision, true);

        if (quoteUsedToRepayDebt > 0) {
            uint256 debtDelta = notional.quoteBorrowClose(uint256(quoteUsedToRepayDebt), instrument, notionalInstrument)
                .fromNotionalPrecision(notionalInstrument.quotePrecision, false);
            if (debtDelta == 0) {
                // TODO alfredo - need to find out how do we cancel de debt 1:1, otherwise this won't be possible
                revert NotImplemented("_calculateCost() - lack of quote lending liquidity - needs 1:1 debt repayment");
            }

            result.debtDelta = -debtDelta.toInt256();
            result.underlyingDebt -= debtDelta;
            if (isIncrease && hedgeCost != 0) {
                // this means we're increasing, and posting more than what we need to pay the spot
                result.needsBatchedCall = true;
            }
        }

        if (quoteUsedToRepayDebt < 0) {
            // should not have liquidity issues here since it's been already verified when calculating collateral
            uint256 fCashBorrow =
                notional.quoteBorrowOpenCost(quoteUsedToRepayDebt.abs(), instrument, notionalInstrument);
            result.debtDelta = fCashBorrow.fromNotionalPrecision(notionalInstrument.quotePrecision, true).toInt256();
            result.underlyingDebt += result.debtDelta.abs();

            if (!isIncrease && hedgeCost != 0) {
                // this means that we're decreasing, and withdrawing more than we get from the spot
                result.needsBatchedCall = true;
            }
        }

        result.financingCost = result.debtDelta + quoteUsedToRepayDebt;
        result.cost -= result.collateralUsed + result.debtDelta;
    }

    function _deliveryCostForPosition(
        PositionId positionId,
        VaultAccount memory vaultAccount,
        NotionalInstrumentStorage memory notionalInstrument,
        Position memory position
    ) internal view returns (DeliveryCostResult memory result) {
        result.deliveryCost = uint256(-vaultAccount.fCash).fromNotionalPrecision(
            notionalInstrument.quotePrecision, true
        ).buffer(notionalInstrument.quotePrecision);
        result.deliveryFee =
            QuoterLib.fee(contangoNotional, positionNFT, positionId, position.symbol, result.deliveryCost);

        result.deliveryCost += position.protocolFees + result.deliveryFee;
    }

    function _validatePosition(PositionId positionId)
        private
        view
        returns (Position memory position, InstrumentData memory instrumentData)
    {
        position = contangoNotional.position(positionId);
        if (position.openQuantity == 0 && position.openCost == 0) {
            if (position.collateral <= 0) {
                revert InvalidPosition(positionId);
            }
        }
        instrumentData = _instrument(position.symbol);
    }

    function _validateActivePosition(PositionId positionId)
        private
        view
        returns (Position memory position, InstrumentData memory instrumentData)
    {
        (position, instrumentData) = _validatePosition(positionId);

        uint256 timestamp = block.timestamp;
        if (instrumentData.instrument.maturity <= timestamp) {
            revert PositionExpired(positionId, instrumentData.instrument.maturity, timestamp);
        }
    }

    function _validateExpiredPosition(PositionId positionId)
        private
        view
        returns (Position memory position, InstrumentData memory instrumentData)
    {
        (position, instrumentData) = _validatePosition(positionId);

        // solhint-disable-next-line not-rely-on-time
        uint256 timestamp = block.timestamp;
        if (instrumentData.instrument.maturity > timestamp) {
            revert PositionActive(positionId, instrumentData.instrument.maturity, timestamp);
        }
    }

    function _instrument(Symbol symbol) private view returns (InstrumentData memory instrumentData) {
        (instrumentData.instrument, instrumentData.notionalInstrument, instrumentData.vault) =
            contangoNotional.notionalInstrument(symbol);
    }

    receive() external payable {
        revert ViewOnly();
    }
}

