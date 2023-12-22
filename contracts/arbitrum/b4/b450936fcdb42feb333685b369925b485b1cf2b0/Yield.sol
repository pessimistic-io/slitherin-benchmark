//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {IPool} from "./IPool.sol";
import {ILadle} from "./ILadle.sol";
import {ICauldron} from "./ICauldron.sol";
import {IFYToken} from "./IFYToken.sol";
import {DataTypes} from "./libraries_DataTypes.sol";
import {IContangoLadle} from "./IContangoLadle.sol";

import "./UniswapV3Handler.sol";
import "./YieldUtils.sol";
import "./SlippageLib.sol";
import "./PositionLib.sol";
import "./Errors.sol";
import "./ExecutionProcessorLib.sol";

library Yield {
    using YieldUtils for *;
    using SignedMath for int256;
    using SafeCast for *;
    using CodecLib for uint256;
    using PositionLib for PositionId;
    using TransferLib for ERC20;

    /// @dev IMPORTANT - make sure the events here are the same as in IContangoEvents
    /// this is needed because we're in a library and can't re-use events from an interface

    event ContractBought(
        Symbol indexed symbol,
        address indexed trader,
        PositionId indexed positionId,
        uint256 size,
        uint256 cost,
        uint256 hedgeSize,
        uint256 hedgeCost,
        int256 collateral
    );
    event ContractSold(
        Symbol indexed symbol,
        address indexed trader,
        PositionId indexed positionId,
        uint256 size,
        uint256 cost,
        uint256 hedgeSize,
        uint256 hedgeCost,
        int256 collateral
    );

    event CollateralAdded(
        Symbol indexed symbol, address indexed trader, PositionId indexed positionId, uint256 amount, uint256 cost
    );
    event CollateralRemoved(
        Symbol indexed symbol, address indexed trader, PositionId indexed positionId, uint256 amount, uint256 cost
    );

    uint128 public constant BORROWING_BUFFER = 5;

    function createPosition(
        Symbol symbol,
        address trader,
        uint256 quantity,
        uint256 limitCost,
        uint256 collateral,
        address payer,
        uint256 lendingLiquidity,
        uint24 uniswapFee
    ) external returns (PositionId positionId) {
        if (quantity == 0) {
            revert InvalidQuantity(int256(quantity));
        }

        positionId = ConfigStorageLib.getPositionNFT().mint(trader);
        positionId.validatePayer(payer, trader);

        StorageLib.getPositionInstrument()[positionId] = symbol;
        InstrumentStorage memory instrument = _createPosition(symbol, positionId);

        _open(
            symbol,
            positionId,
            trader,
            instrument,
            quantity,
            limitCost,
            collateral.toInt256(),
            payer,
            lendingLiquidity,
            uniswapFee
        );
    }

    function modifyPosition(
        PositionId positionId,
        int256 quantity,
        uint256 limitCost,
        int256 collateral,
        address payerOrReceiver,
        uint256 lendingLiquidity,
        uint24 uniswapFee
    ) external {
        if (quantity == 0) {
            revert InvalidQuantity(quantity);
        }

        (uint256 openQuantity, address trader, Symbol symbol, InstrumentStorage memory instrument) =
            positionId.loadActivePosition();
        if (collateral > 0) {
            positionId.validatePayer(payerOrReceiver, trader);
        }

        if (quantity < 0 && uint256(-quantity) > openQuantity) {
            revert InvalidPositionDecrease(positionId, quantity, openQuantity);
        }

        if (quantity > 0) {
            _open(
                symbol,
                positionId,
                trader,
                instrument,
                uint256(quantity),
                limitCost,
                collateral,
                payerOrReceiver,
                lendingLiquidity,
                uniswapFee
            );
        } else {
            _close(
                symbol,
                positionId,
                trader,
                instrument,
                uint256(-quantity),
                limitCost,
                collateral,
                payerOrReceiver,
                lendingLiquidity,
                uniswapFee
            );

            if (uint256(-quantity) == openQuantity) {
                _deletePosition(positionId);
            }
        }
    }

    function collateralBought(bytes12 vaultId, uint256 ink, uint256 art) external {
        PositionId positionId = PositionId.wrap(uint96(vaultId));
        ExecutionProcessorLib.liquidatePosition(
            StorageLib.getPositionInstrument()[positionId],
            positionId,
            ConfigStorageLib.getPositionNFT().positionOwner(positionId),
            ink,
            art
        );
    }

    function _createPosition(Symbol symbol, PositionId positionId)
        private
        returns (InstrumentStorage memory instrument)
    {
        YieldInstrumentStorage storage yieldInsturment;
        (instrument, yieldInsturment) = symbol.loadInstrument();

        // solhint-disable-next-line not-rely-on-time
        if (instrument.maturity < block.timestamp) {
            // solhint-disable-next-line not-rely-on-time
            revert InstrumentExpired(symbol, instrument.maturity, block.timestamp);
        }

        YieldStorageLib.getLadle().deterministicBuild(
            positionId.toVaultId(), yieldInsturment.quoteId, yieldInsturment.baseId
        );
    }

    function _deletePosition(PositionId positionId) private {
        positionId.deletePosition();
        YieldStorageLib.getLadle().destroy(positionId.toVaultId());
    }

    function _open(
        Symbol symbol,
        PositionId positionId,
        address trader,
        InstrumentStorage memory instrument,
        uint256 quantity,
        uint256 limitCost,
        int256 collateral,
        address payerOrReceiver,
        uint256 lendingLiquidity,
        uint24 uniswapFee
    ) private {
        if (instrument.closingOnly) {
            revert InstrumentClosingOnly(symbol);
        }

        UniswapV3Handler.CallbackInfo memory callbackInfo = UniswapV3Handler.CallbackInfo({
            symbol: symbol,
            positionId: positionId,
            trader: trader,
            limitCost: limitCost,
            payerOrReceiver: payerOrReceiver,
            open: true,
            lendingLiquidity: lendingLiquidity,
            uniswapFee: uniswapFee
        });

        IPool basePool = YieldStorageLib.getInstruments()[symbol].basePool;
        address receiver = lendingLiquidity < quantity ? address(this) : address(basePool);

        // Use a flash swap to buy enough base to hedge the position, pay directly to the pool where we'll lend it
        _flashBuyHedge(instrument, basePool, callbackInfo, quantity, collateral, receiver);
    }

    /// @dev Second step of trading, this executes on the back of the flash swap callback,
    /// it will pay part of the swap by using the trader collateral,
    /// then will borrow the rest from the lending protocol. Fill cost == swap cost + loan interest.
    /// @param callback Info collected before the flash swap started
    function completeOpen(UniswapV3Handler.Callback memory callback) internal {
        YieldInstrumentStorage storage yieldInstrument = YieldStorageLib.getInstruments()[callback.info.symbol];

        uint128 ink = callback.fill.size.toUint128();

        // Lend the base we just flash bought
        _openLendingPosition(yieldInstrument, callback, ink);

        // Use the payer collateral (if any) to pay part/all of the flash swap
        if (callback.fill.collateral > 0) {
            // Trader can contribute up to the spot cost
            callback.fill.collateral = SignedMath.min(callback.fill.collateral, callback.fill.hedgeCost.toInt256());
            callback.instrument.quote.transferOut(
                callback.info.payerOrReceiver, msg.sender, uint256(callback.fill.collateral)
            );
        }

        uint128 amountToBorrow = (callback.fill.hedgeCost.toInt256() - callback.fill.collateral).toUint256().toUint128();
        uint128 art;

        // If the collateral wasn't enough to cover the whole trade
        if (amountToBorrow != 0) {
            // Math is not exact anymore with the PoolEuler, so we need to borrow a bit more
            amountToBorrow += BORROWING_BUFFER;
            // How much debt at future value (art) do I need to take on in order to get enough cash at present value (remainder)
            art = yieldInstrument.quotePool.buyBasePreview(amountToBorrow);
        }

        // Deposit collateral (ink) and take on debt if necessary (art)
        YieldStorageLib.getLadle().pour(
            callback.info.positionId.toVaultId(), // Vault that will issue the debt & store the collateral
            address(yieldInstrument.quotePool), // If taking any debt, send it to the pool so it can be sold
            ink.toInt256().toInt128(), // Use the fyTokens we bought using the flash swap as ink (collateral)
            art.toInt256().toInt128() // Amount to borrow in future value
        );

        address sendBorrowedFundsTo;

        if (callback.fill.collateral < 0) {
            // We need to keep the borrowed funds in this contract so we can pay both the trader and uniswap
            sendBorrowedFundsTo = address(this);
            // Cost is spot + financing costs
            callback.fill.cost = callback.fill.hedgeCost + (art - amountToBorrow);
        } else {
            // We can pay to uniswap directly as it's the only reason we are borrowing for
            sendBorrowedFundsTo = msg.sender;
            // Cost is spot + debt + financing costs
            callback.fill.cost = art + uint256(callback.fill.collateral);
        }

        SlippageLib.requireCostBelowTolerance(callback.fill.cost, callback.info.limitCost);

        if (amountToBorrow != 0) {
            // Sell the fyTokens for actual cash (borrow)
            yieldInstrument.quotePool.buyBase({to: sendBorrowedFundsTo, baseOut: amountToBorrow, max: art});
        }

        // Pay uniswap if necessary
        if (sendBorrowedFundsTo == address(this)) {
            callback.instrument.quote.transferOut(address(this), msg.sender, callback.fill.hedgeCost);
        }

        ExecutionProcessorLib.increasePosition(
            callback.info.symbol,
            callback.info.positionId,
            callback.info.trader,
            callback.fill.size,
            callback.fill.cost,
            callback.fill.collateral,
            callback.instrument.quote,
            callback.info.payerOrReceiver,
            yieldInstrument.minQuoteDebt
        );

        emit ContractBought(
            callback.info.symbol,
            callback.info.trader,
            callback.info.positionId,
            callback.fill.size,
            callback.fill.cost,
            callback.fill.hedgeSize,
            callback.fill.hedgeCost,
            callback.fill.collateral
        );
    }

    function _close(
        Symbol symbol,
        PositionId positionId,
        address trader,
        InstrumentStorage memory instrument,
        uint256 quantity,
        uint256 limitCost,
        int256 collateral,
        address payerOrReceiver,
        uint256 lendingLiquidity,
        uint24 uniswapFee
    ) private {
        // Execute a flash swap to undo the hedge
        _flashSellHedge(
            instrument,
            YieldStorageLib.getInstruments()[symbol].basePool,
            UniswapV3Handler.CallbackInfo({
                symbol: symbol,
                positionId: positionId,
                limitCost: limitCost,
                trader: trader,
                payerOrReceiver: payerOrReceiver,
                open: false,
                lendingLiquidity: lendingLiquidity,
                uniswapFee: uniswapFee
            }),
            quantity,
            collateral,
            address(this) // We must receive the funds ourselves cause the TV pools have a bug & will consume them all otherwise
        );
    }

    /// @dev Second step to reduce/close a position. This executes on the back of the flash swap callback,
    /// then it will repay debt using the proceeds from the flash swap and deal with any excess appropriately.
    /// @param callback Info collected before the flash swap started
    function completeClose(UniswapV3Handler.Callback memory callback) internal {
        YieldInstrumentStorage storage yieldInstrument = YieldStorageLib.getInstruments()[callback.info.symbol];
        DataTypes.Balances memory balances =
            YieldStorageLib.getCauldron().balances(callback.info.positionId.toVaultId());
        bool fullyClosing = callback.fill.size == balances.ink;
        int128 art;

        // If there's any debt to repay
        if (balances.art != 0) {
            // Use the quote we just bought to buy/mint fyTokens to reduce the debt and free up the amount we owe for the flash loan
            if (fullyClosing) {
                // If we're fully closing, pay all debt
                art = -balances.art.toInt256().toInt128();
                // Buy the exact amount of (fy)Quote we owe (art) using the money from the flash swap (money was sent directly to the quotePool).
                // Send the tokens to the fyToken contract so they can be burnt
                // Cost == swap cost + pnl of cancelling the debt
                uint128 baseIn = _buyFYToken({
                    pool: yieldInstrument.quotePool,
                    underlying: callback.instrument.quote,
                    fyToken: yieldInstrument.quoteFyToken,
                    to: address(yieldInstrument.quoteFyToken),
                    fyTokenOut: balances.art,
                    lendingLiquidity: callback.info.lendingLiquidity,
                    excessExpected: true
                });
                callback.fill.cost = callback.fill.hedgeCost + (balances.art - baseIn);
            } else {
                // Can't withdraw more than what we got from UNI
                if (callback.fill.collateral < 0) {
                    callback.fill.collateral =
                        SignedMath.max(callback.fill.collateral, -int256(callback.fill.hedgeCost));
                }

                int256 quoteUsedToRepayDebt = callback.fill.collateral + int256(callback.fill.hedgeCost);

                if (quoteUsedToRepayDebt > 0) {
                    // If the user is depositing, take the necessary tokens from the payer
                    if (callback.fill.collateral > 0) {
                        callback.instrument.quote.transferOut({
                            payer: callback.info.payerOrReceiver,
                            to: address(this),
                            amount: uint256(callback.fill.collateral)
                        });
                    }

                    // Under normal circumstances, send the required funds to the pool
                    if (uint256(quoteUsedToRepayDebt) < callback.info.lendingLiquidity) {
                        callback.instrument.quote.transferOut({
                            payer: address(this),
                            to: address(yieldInstrument.quotePool),
                            amount: uint256(quoteUsedToRepayDebt)
                        });
                    }

                    // Sell available base tokens for fyTokens to repay debt
                    art = -_sellBaseOrMint({
                        pool: yieldInstrument.quotePool,
                        underlying: callback.instrument.quote,
                        fyToken: yieldInstrument.quoteFyToken,
                        availableBase: uint256(quoteUsedToRepayDebt).toUint128(),
                        lendingLiquidity: callback.info.lendingLiquidity
                    }).toInt256().toInt128();
                }

                callback.fill.cost = (-(callback.fill.collateral + art)).toUint256();
            }
        } else {
            // Given there's no debt, the cost is the hedgeCost
            callback.fill.cost = callback.fill.hedgeCost;
        }

        SlippageLib.requireCostAboveTolerance(callback.fill.cost, callback.info.limitCost);

        // Retrieve real base ccy and pay the flash swap
        _closeLendingPosition(yieldInstrument, callback, art);

        emit ContractSold(
            callback.info.symbol,
            callback.info.trader,
            callback.info.positionId,
            callback.fill.size,
            callback.fill.cost,
            callback.fill.hedgeSize,
            callback.fill.hedgeCost,
            callback.fill.collateral
        );

        if (fullyClosing) {
            ExecutionProcessorLib.closePosition(
                callback.info.symbol,
                callback.info.positionId,
                callback.info.trader,
                callback.fill.cost,
                callback.instrument.quote,
                callback.info.payerOrReceiver
            );
        } else {
            ExecutionProcessorLib.decreasePosition(
                callback.info.symbol,
                callback.info.positionId,
                callback.info.trader,
                callback.fill.size,
                callback.fill.cost,
                callback.fill.collateral,
                callback.instrument.quote,
                callback.info.payerOrReceiver,
                yieldInstrument.minQuoteDebt
            );
        }
    }

    // ============== Physical delivery ==============

    function deliver(PositionId positionId, address payer, address to) external {
        address trader = positionId.lookupPositionOwner();
        positionId.validatePayer(payer, trader);

        (, Symbol symbol, InstrumentStorage memory instrument) = positionId.validateExpiredPosition();

        _deliver(symbol, positionId, trader, instrument, payer, to);

        _deletePosition(positionId);
    }

    function _deliver(
        Symbol symbol,
        PositionId positionId,
        address trader,
        InstrumentStorage memory instrument,
        address payer,
        address to
    ) private {
        YieldInstrumentStorage storage yieldInstrument = YieldStorageLib.getInstruments()[symbol];
        IFYToken baseFyToken = yieldInstrument.baseFyToken;
        ILadle ladle = YieldStorageLib.getLadle();
        ICauldron cauldron = YieldStorageLib.getCauldron();
        DataTypes.Balances memory balances = cauldron.balances(positionId.toVaultId());

        uint256 requiredQuote;
        if (balances.art != 0) {
            bytes6 quoteId = yieldInstrument.quoteId;

            // we need to cater for the interest rate accrued after maturity
            requiredQuote = cauldron.debtToBase(quoteId, balances.art);

            // Send the requiredQuote to the Join
            instrument.quote.transferOut(payer, address(ladle.joins(cauldron.series(quoteId).baseId)), requiredQuote);

            ladle.close(
                positionId.toVaultId(),
                address(baseFyToken), // Send ink to be redeemed on the FYToken contract
                -int128(balances.ink), // withdraw ink
                -int128(balances.art) // repay art
            );
        } else {
            ladle.pour(
                positionId.toVaultId(),
                address(baseFyToken), // Send ink to be redeemed on the FYToken contract
                -int128(balances.ink), // withdraw ink
                0 // no debt to repay
            );
        }

        ExecutionProcessorLib.deliverPosition(
            symbol,
            positionId,
            trader,
            // Burn fyTokens in exchange for underlying, send underlying to `to`
            baseFyToken.redeem(to, balances.ink),
            requiredQuote,
            payer,
            instrument.quote,
            to
        );
    }

    // ============== Collateral management ==============

    function modifyCollateral(
        PositionId positionId,
        int256 collateral,
        uint256 slippageTolerance,
        address payerOrReceiver,
        uint256 lendingLiquidity
    ) external {
        // uniswapFee is irrelevant as there'll be no trade on UNI
        (, address trader, Symbol symbol, InstrumentStorage memory instrument) = positionId.loadActivePosition();

        if (collateral > 0) {
            positionId.validatePayer(payerOrReceiver, trader);
            _addCollateral(
                symbol,
                positionId,
                trader,
                instrument,
                uint256(collateral),
                slippageTolerance,
                payerOrReceiver,
                lendingLiquidity
            );
        }
        if (collateral < 0) {
            _removeCollateral(symbol, positionId, trader, uint256(-collateral), slippageTolerance, payerOrReceiver);
        }
    }

    function _addCollateral(
        Symbol symbol,
        PositionId positionId,
        address trader,
        InstrumentStorage memory instrument,
        uint256 collateral,
        uint256 slippageTolerance,
        address payer,
        uint256 lendingLiquidity
    ) private {
        YieldInstrumentStorage storage yieldInstrument = YieldStorageLib.getInstruments()[symbol];
        IPool quotePool = yieldInstrument.quotePool;

        address to = collateral > lendingLiquidity ? address(this) : address(quotePool);
        if (to != payer) {
            // Collect the new collateral from the payer and send wherever's appropriate
            instrument.quote.transferOut({payer: payer, to: to, amount: collateral});
        }

        // Sell the collateral and get as much (fy)Quote (art) as possible
        uint256 art = _sellBaseOrMint({
            pool: quotePool,
            underlying: instrument.quote,
            fyToken: yieldInstrument.quoteFyToken,
            availableBase: collateral.toUint128(),
            lendingLiquidity: lendingLiquidity
        });

        SlippageLib.requireCostAboveTolerance(art, slippageTolerance);

        // Use the (fy)Quote (art) we bought to burn debt on the vault
        YieldStorageLib.getLadle().pour(
            positionId.toVaultId(),
            address(0), // We're not taking new debt, so no need to pass an address
            0, // We're not changing the collateral
            -art.toInt256().toInt128() // We burn all the (fy)Quote we just bought
        );

        // The interest pnl is reflected on the position cost
        int256 cost = -(art - collateral).toInt256();

        // cast to int is safe as we prev casted to uint128
        ExecutionProcessorLib.updateCollateral(symbol, positionId, trader, cost, int256(collateral));

        emit CollateralAdded(symbol, trader, positionId, collateral, art);
    }

    function _removeCollateral(
        Symbol symbol,
        PositionId positionId,
        address trader,
        uint256 collateral,
        uint256 slippageTolerance,
        address to
    ) private {
        // Borrow whatever the trader wants to withdraw
        uint128 art = YieldStorageLib.getLadle().serve(
            positionId.toVaultId(),
            to, // Send the borrowed funds directly
            0, // We don't deposit any new collateral
            collateral.toUint128(), // Amount to borrow
            type(uint128).max // We don't need slippage control here, we have a general check below
        );

        SlippageLib.requireCostBelowTolerance(art, slippageTolerance);

        // The interest pnl is reflected on the position cost
        int256 cost = (art - collateral).toInt256();

        // cast to int is safe as we prev casted to uint128
        ExecutionProcessorLib.updateCollateral(symbol, positionId, trader, cost, -int256(collateral));

        emit CollateralRemoved(symbol, trader, positionId, collateral, art);
    }

    // ============== Uniswap functions ==============

    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external {
        UniswapV3Handler.uniswapV3SwapCallback(amount0Delta, amount1Delta, data, _onUniswapCallback);
    }

    function _onUniswapCallback(UniswapV3Handler.Callback memory callback) internal {
        callback.info.open ? completeOpen(callback) : completeClose(callback);
    }

    function _flashBuyHedge(
        InstrumentStorage memory instrument,
        IPool basePool,
        UniswapV3Handler.CallbackInfo memory callbackInfo,
        uint256 quantity,
        int256 collateral,
        address to
    ) private {
        UniswapV3Handler.Callback memory callback;

        callback.info = callbackInfo;
        callback.fill.size = quantity;
        callback.fill.collateral = collateral;
        callback.fill.hedgeSize = _buyFYTokenPreview(basePool, quantity.toUint128(), callbackInfo.lendingLiquidity);

        UniswapV3Handler.flashSwap({callback: callback, instrument: instrument, baseForQuote: false, to: to});
    }

    function _flashSellHedge(
        InstrumentStorage memory instrument,
        IPool basePool,
        UniswapV3Handler.CallbackInfo memory callbackInfo,
        uint256 quantity,
        int256 collateral,
        address to
    ) private {
        UniswapV3Handler.Callback memory callback;

        callback.info = callbackInfo;
        callback.fill.size = quantity;
        callback.fill.collateral = collateral;
        callback.fill.hedgeSize =
            YieldStorageLib.getCauldron().closeLendingPositionPreview(basePool, callback.info.positionId, quantity);

        UniswapV3Handler.flashSwap({callback: callback, instrument: instrument, baseForQuote: true, to: to});
    }

    // ============== Private functions ==============

    function _sellBaseOrMint(
        IPool pool,
        ERC20 underlying,
        IFYToken fyToken,
        uint128 availableBase,
        uint256 lendingLiquidity
    ) private returns (uint128 fyTokenOut) {
        if (availableBase > lendingLiquidity) {
            uint128 maxBaseIn = lendingLiquidity.toUint128();
            fyTokenOut = pool.sellBasePreviewZero(maxBaseIn);
            if (fyTokenOut > 0) {
                // Transfer max amount that can be sold
                underlying.transferOut({payer: address(this), to: address(pool), amount: maxBaseIn});
                // Sell limited amount to the pool
                fyTokenOut = pool.sellBase({to: address(fyToken), min: fyTokenOut});
            } else {
                maxBaseIn = 0;
            }

            fyTokenOut += _forceLend(underlying, fyToken, address(fyToken), availableBase - maxBaseIn);
        } else {
            fyTokenOut = pool.sellBase({to: address(fyToken), min: availableBase});
        }
    }

    function _buyFYTokenPreview(IPool pool, uint128 fyTokenOut, uint256 lendingLiquidity)
        private
        view
        returns (uint128 baseIn)
    {
        if (fyTokenOut > lendingLiquidity) {
            uint128 maxFYTokenOut = uint128(lendingLiquidity);
            baseIn = maxFYTokenOut == 0
                ? fyTokenOut
                : fyTokenOut - maxFYTokenOut + pool.buyFYTokenPreviewFixed(maxFYTokenOut);
        } else {
            baseIn = pool.buyFYTokenPreviewFixed(fyTokenOut);
        }
    }

    function _buyFYToken(
        IPool pool,
        ERC20 underlying,
        IFYToken fyToken,
        address to,
        uint128 fyTokenOut,
        uint256 lendingLiquidity,
        bool excessExpected
    ) private returns (uint128 baseIn) {
        if (fyTokenOut > lendingLiquidity) {
            uint128 maxFYTokenOut = uint128(lendingLiquidity);

            if (maxFYTokenOut > 0) {
                baseIn = _buyFYToken(pool, underlying, to, maxFYTokenOut);
            }

            baseIn += _forceLend(underlying, fyToken, to, fyTokenOut - maxFYTokenOut);
        } else {
            baseIn = excessExpected
                ? _buyFYToken(pool, underlying, to, fyTokenOut)
                : pool.buyFYToken(to, fyTokenOut, type(uint128).max);
        }
    }

    function _buyFYToken(IPool pool, ERC20 underlying, address to, uint128 fyTokenOut)
        private
        returns (uint128 baseIn)
    {
        baseIn = uint128(underlying.transferOut(address(this), address(pool), pool.buyFYTokenPreviewFixed(fyTokenOut)));
        pool.buyFYToken(to, fyTokenOut, type(uint128).max);
    }

    function _forceLend(ERC20 underlying, IFYToken fyToken, address to, uint128 toMint) internal returns (uint128) {
        underlying.transferOut(address(this), address(fyToken.join()), toMint);
        fyToken.mintWithUnderlying(to, toMint);
        return toMint;
    }

    function _openLendingPosition(
        YieldInstrumentStorage storage yieldInstrument,
        UniswapV3Handler.Callback memory callback,
        uint128 fyTokenOut
    ) internal {
        address to = YieldStorageLib.getJoins()[yieldInstrument.baseId];
        if (fyTokenOut > callback.info.lendingLiquidity) {
            uint128 maxFYTokenOut = uint128(callback.info.lendingLiquidity);

            if (maxFYTokenOut > 0) {
                _buyFYToken(yieldInstrument.basePool, callback.instrument.base, to, maxFYTokenOut);
            }

            _wrapBaseInFYTokens(yieldInstrument, callback, fyTokenOut - maxFYTokenOut, to);
        } else {
            yieldInstrument.basePool.buyFYToken({
                to: to, // send the (fy)Base to the join so it can be used as collateral for borrowing
                fyTokenOut: fyTokenOut,
                max: type(uint128).max
            });
        }
    }

    function _wrapBaseInFYTokens(
        YieldInstrumentStorage storage yieldInstrument,
        UniswapV3Handler.Callback memory callback,
        uint128 toWrap,
        address to
    ) internal {
        IContangoLadle ladle = YieldStorageLib.getLadle();
        ICauldron cauldron = YieldStorageLib.getCauldron();
        bytes12 baseVaultId = callback.info.positionId.toBaseVaultId();
        DataTypes.Vault memory baseVault = cauldron.vaults(baseVaultId);
        if (baseVault.owner == address(0)) {
            baseVault = ladle.deterministicBuild(
                baseVaultId, yieldInstrument.baseId, cauldron.series(yieldInstrument.baseId).baseId
            );
        }
        callback.instrument.base.transferOut(address(this), address(yieldInstrument.baseFyToken.join()), toWrap);
        ladle.pour(baseVaultId, to, int128(toWrap), int128(toWrap));
    }

    function _closeLendingPosition(
        YieldInstrumentStorage storage yieldInstrument,
        UniswapV3Handler.Callback memory callback,
        int128 art
    ) internal {
        uint128 amountToRepay = uint128(callback.fill.hedgeSize);

        IContangoLadle ladle = YieldStorageLib.getLadle();
        bytes12 baseVaultId = callback.info.positionId.toBaseVaultId();
        uint256 wrappedBase = YieldStorageLib.getCauldron().balances(baseVaultId).ink;

        // Burn debt and withdraw collateral from Yield, send the collateral directly to the basePool so it can be sold, or to this contract if we can uwrap it
        ladle.pour({
            vaultId_: callback.info.positionId.toVaultId(),
            to: wrappedBase > 0 ? address(this) : address(yieldInstrument.basePool),
            ink: -int256(callback.fill.size).toInt128(),
            art: art
        });

        if (wrappedBase > 0) {
            uint128 amountToUnwrap = uint128(Math.min(amountToRepay, wrappedBase));
            ERC20(address(yieldInstrument.baseFyToken)).transferOut(
                address(this), address(yieldInstrument.baseFyToken), amountToUnwrap
            );
            ladle.pour(baseVaultId, msg.sender, -int128(amountToUnwrap), -int128(amountToUnwrap));

            amountToRepay = uint128(callback.fill.size) - amountToUnwrap;
            ERC20(address(yieldInstrument.baseFyToken)).transferOut(
                address(this), address(yieldInstrument.basePool), amountToRepay
            );
        }

        // Sell collateral (ink) to pay for the flash swap, the amount of ink was pre-calculated to obtain the exact cost of the swap
        if (amountToRepay > 0) {
            yieldInstrument.basePool.sellFYToken(msg.sender, 0);
        }
    }
}

