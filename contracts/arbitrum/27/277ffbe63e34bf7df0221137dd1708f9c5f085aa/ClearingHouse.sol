// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import { IERC20 } from "./IERC20.sol";
import { Decimal } from "./Decimal.sol";
import { SignedDecimal } from "./SignedDecimal.sol";
import { MixedDecimal } from "./MixedDecimal.sol";
import { DecimalERC20 } from "./DecimalERC20.sol";
import { ReentrancyGuardUpgradeable } from "./ReentrancyGuardUpgradeable.sol";
import { OwnerPausableUpgradeable } from "./OwnerPausable.sol";
import { IAmm } from "./IAmm.sol";
import { IInsuranceFund } from "./IInsuranceFund.sol";

/**
                                                                              
                            ####
                        @@@@    @@@@                      
                    /@@@            @@@\
                @@@@                    @@@@
            /@@@                            @@@\
        /@@@                                    @@@\
    /@@@                                            @@@\
 ////   ############################################   \\\\
 █▀▀ █░░ █▀▀ ▄▀█ █▀█ █ █▄░█ █▀▀   █░█ █▀█ █░█ █▀ █▀▀
 █▄▄ █▄▄ ██▄ █▀█ █▀▄ █ █░▀█ █▄█   █▀█ █▄█ █▄█ ▄█ ██▄                                        
#############################################################                                                    
            @@   @@       @@   @@       @@   @@
            @@   @@       @@   @@       @@   @@       
            @@   @@       @@   @@       @@   @@       
            @@   @@       @@   @@       @@   @@       
            @@   @@       @@   @@       @@   @@       
            @@   @@       @@   @@       @@   @@       
            @@   @@       @@   @@       @@   @@       
            @@   @@       @@   @@       @@   @@       
        ...........................................                                                    
    @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
...........................................................
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

 */

/**
 * @title Clearing House
 * @notice
 * - issues and stores positions of traders
 * - settles all collateral between traders
 */
contract ClearingHouse is DecimalERC20, OwnerPausableUpgradeable, ReentrancyGuardUpgradeable {
    using Decimal for Decimal.decimal;
    using SignedDecimal for SignedDecimal.signedDecimal;
    using MixedDecimal for SignedDecimal.signedDecimal;

    /// @notice BUY = LONG, SELL = SHORT
    enum Side {
        BUY,
        SELL
    }

    /**
     * @title Position
     * @notice This struct records position information
     * @param size denominated in amm.baseAsset
     * @param margin isolated margin (collateral amt)
     * @param openNotional the quoteAsset value of the position. the cost of the position
     * @param lastUpdatedCumulativePremiumFraction for calculating funding payment, recorded at position update
     * @param blockNumber recorded at every position update
     */
    struct Position {
        SignedDecimal.signedDecimal size;
        Decimal.decimal margin;
        Decimal.decimal openNotional;
        SignedDecimal.signedDecimal lastUpdatedCumulativePremiumFractionLong;
        SignedDecimal.signedDecimal lastUpdatedCumulativePremiumFractionShort;
        uint256 blockNumber;
    }

    /// @notice records vault position sizes
    struct TotalPositionSize {
        SignedDecimal.signedDecimal netPositionSize;
        Decimal.decimal positionSizeLong;
        Decimal.decimal positionSizeShort;
    }

    /// @notice used for avoiding stack too deep error
    struct PositionResp {
        Position position;
        Decimal.decimal exchangedQuoteAssetAmount;
        Decimal.decimal badDebt;
        SignedDecimal.signedDecimal exchangedPositionSize;
        SignedDecimal.signedDecimal fundingPayment;
        SignedDecimal.signedDecimal realizedPnl;
        SignedDecimal.signedDecimal marginToVault;
        SignedDecimal.signedDecimal unrealizedPnlAfter;
    }

    /// @notice used for avoiding stack too deep error
    struct CalcRemainMarginReturnParams {
        SignedDecimal.signedDecimal latestCumulativePremiumFractionLong;
        SignedDecimal.signedDecimal latestCumulativePremiumFractionShort;
        SignedDecimal.signedDecimal fundingPayment;
        Decimal.decimal badDebt;
        Decimal.decimal remainingMargin;
    }

    //
    // STATE VARS
    //

    IInsuranceFund public insuranceFund;
    Decimal.decimal public fundingRateDeltaCapRatio;

    // key by amm address
    mapping(address => mapping(address => Position)) public positionMap;
    mapping(address => Decimal.decimal) public openInterestNotionalMap;
    mapping(address => TotalPositionSize) public totalPositionSizeMap;
    mapping(address => SignedDecimal.signedDecimal[]) public cumulativePremiumFractionLong;
    mapping(address => SignedDecimal.signedDecimal[]) public cumulativePremiumFractionShort;
    mapping(address => address) public repegBots;

    // key by token
    mapping(address => Decimal.decimal) public tollMap;

    //
    // EVENTS
    //

    /**
     * @notice This event is emitted when position is changed
     * @param trader - trader
     * @param amm - amm
     * @param margin - updated margin
     * @param exchangedPositionNotional - the position notional exchanged in the trade
     * @param exchangedPositionSize - the position size exchanged in the trade
     * @param fee - trade fee
     * @param positionSizeAfter - updated position size
     * @param realizedPnl - realized pnl on the trade
     * @param unrealizedPnlAfter - unrealized pnl remaining after the trade
     * @param badDebt - margin cleared by insurance fund (optimally 0)
     * @param liquidationPenalty - liquidation fee
     * @param markPrice - updated mark price
     * @param fundingPayment - funding payment (+: paid, -: received)
     */
    event PositionChanged(
        address indexed trader,
        address indexed amm,
        uint256 margin,
        uint256 exchangedPositionNotional,
        int256 exchangedPositionSize,
        uint256 fee,
        int256 positionSizeAfter,
        int256 realizedPnl,
        int256 unrealizedPnlAfter,
        uint256 badDebt,
        uint256 liquidationPenalty,
        uint256 markPrice,
        int256 fundingPayment
    );

    /**
     * @notice This event is emitted when position is liquidated
     * @param trader - trader
     * @param amm - amm
     * @param liquidator - liquidator
     * @param liquidatedPositionNotional - liquidated position notional
     * @param liquidatedPositionSize - liquidated position size
     * @param liquidationReward - liquidation reward to the liquidator
     * @param insuranceFundProfit - insurance fund profit on liquidation
     * @param badDebt - liquidation fee cleared by insurance fund (optimally 0)
     */
    event PositionLiquidated(
        address indexed trader,
        address indexed amm,
        address indexed liquidator,
        uint256 liquidatedPositionNotional,
        uint256 liquidatedPositionSize,
        uint256 liquidationReward,
        uint256 insuranceFundProfit,
        uint256 badDebt
    );

    /**
     * @notice emitted on funding payments
     * @param amm - amm
     * @param markPrice - mark price on funding
     * @param indexPrice - index price on funding
     * @param premiumFractionLong - total premium longs pay (when +ve), receive (when -ve)
     * @param premiumFractionShort - total premium shorts receive (when +ve), pay (when -ve)
     * @param insuranceFundPnl - insurance fund pnl from funding
     */
    event FundingPayment(
        address indexed amm,
        uint256 markPrice,
        uint256 indexPrice,
        int256 premiumFractionLong,
        int256 premiumFractionShort,
        int256 insuranceFundPnl
    );

    /**
     * @notice emitted on adding or removing margin
     * @param trader - trader address
     * @param amm - amm address
     * @param amount - amount changed
     * @param fundingPayment - funding payment
     */
    event MarginChanged(
        address indexed trader,
        address indexed amm,
        int256 amount,
        int256 fundingPayment
    );

    /**
     * @notice emitted on repeg (convergence event)
     * @param amm - amm address
     * @param quoteAssetReserveBefore - quote reserve before repeg
     * @param baseAssetReserveBefore - base reserve before repeg
     * @param quoteAssetReserveAfter - quote reserve after repeg
     * @param baseAssetReserveAfter - base reserve after repeg
     * @param repegPnl - effective pnl incurred on vault positions after repeg
     * @param repegDebt - amount borrowed from insurance fund
     */
    event Repeg(
        address indexed amm,
        uint256 quoteAssetReserveBefore,
        uint256 baseAssetReserveBefore,
        uint256 quoteAssetReserveAfter,
        uint256 baseAssetReserveAfter,
        int256 repegPnl,
        uint256 repegDebt
    );

    /// @notice emitted on setting repeg bots
    event RepegBotSet(address indexed amm, address indexed bot);

    modifier onlyRepegBot(IAmm _amm) {
        address sender = _msgSender();
        require(sender == repegBots[address(_amm)] || sender == owner(), "not allowed");
        _;
    }

    //
    // EXTERNAL
    //

    function initialize(IInsuranceFund _insuranceFund, uint256 _fundingRateDeltaCapRatio)
        external
        initializer
    {
        require(address(_insuranceFund) != address(0), "addr(0)");
        __OwnerPausable_init();
        __ReentrancyGuard_init();

        insuranceFund = _insuranceFund;
        fundingRateDeltaCapRatio = Decimal.decimal(_fundingRateDeltaCapRatio);
    }

    /**
     * @notice open a position
     * @param _amm amm address
     * @param _side enum Side; BUY for long and SELL for short
     * @param _quoteAssetAmount quote asset amount in 18 digits. Can Not be 0
     * @param _leverage leverage in 18 digits. Can Not be 0
     * @param _baseAssetAmountLimit base asset amount limit in 18 digits (slippage). 0 for any slippage
     */
    function openPosition(
        IAmm _amm,
        Side _side,
        Decimal.decimal memory _quoteAssetAmount,
        Decimal.decimal memory _leverage,
        Decimal.decimal memory _baseAssetAmountLimit
    ) external whenNotPaused nonReentrant {
        _requireAmm(_amm);
        _requireNonZeroInput(_quoteAssetAmount);
        _requireNonZeroInput(_leverage);
        _requireMoreMarginRatio(
            MixedDecimal.fromDecimal(Decimal.one()).divD(_leverage),
            _amm.getRatios().initMarginRatio,
            true
        );
        _requireNonSandwich(_amm);

        address trader = _msgSender();
        PositionResp memory positionResp;
        // add scope for stack too deep error
        {
            int256 oldPositionSize = getPosition(_amm, trader).size.toInt();
            bool isNewPosition = oldPositionSize == 0 ? true : false;

            // increase or decrease position depends on old position's side and size
            if (isNewPosition || (oldPositionSize > 0 ? Side.BUY : Side.SELL) == _side) {
                positionResp = _internalIncreasePosition(
                    _amm,
                    _side,
                    _quoteAssetAmount.mulD(_leverage),
                    _baseAssetAmountLimit,
                    _leverage
                );
            } else {
                positionResp = _openReversePosition(
                    _amm,
                    _side,
                    trader,
                    _quoteAssetAmount,
                    _leverage,
                    _baseAssetAmountLimit,
                    false
                );
            }

            // update position
            setPosition(_amm, trader, positionResp.position);
            // opening opposite exact position size as the existing one == closePosition, can skip the margin ratio check
            if (!isNewPosition && positionResp.position.size.toInt() != 0) {
                _requireMoreMarginRatio(
                    getMarginRatio(_amm, trader),
                    _amm.getRatios().maintenanceMarginRatio,
                    true
                );
            }

            require(positionResp.badDebt.toUint() == 0, "bad debt");

            // transfer the token between trader and vault
            IERC20 quoteToken = _amm.quoteAsset();
            if (positionResp.marginToVault.toInt() > 0) {
                _transferFrom(quoteToken, trader, address(this), positionResp.marginToVault.abs());
            } else if (positionResp.marginToVault.toInt() < 0) {
                _withdraw(quoteToken, trader, positionResp.marginToVault.abs());
            }
        }

        // fees
        Decimal.decimal memory fees = _transferFees(
            trader,
            _amm,
            positionResp.exchangedQuoteAssetAmount,
            _side
        );

        // emit event
        uint256 markPrice = _amm.getMarkPrice().toUint();
        int256 fundingPayment = positionResp.fundingPayment.toInt(); // pre-fetch for stack too deep error
        emit PositionChanged(
            trader,
            address(_amm),
            positionResp.position.margin.toUint(),
            positionResp.exchangedQuoteAssetAmount.toUint(),
            positionResp.exchangedPositionSize.toInt(),
            fees.toUint(),
            positionResp.position.size.toInt(),
            positionResp.realizedPnl.toInt(),
            positionResp.unrealizedPnlAfter.toInt(),
            positionResp.badDebt.toUint(),
            0,
            markPrice,
            fundingPayment
        );
    }

    /**
     * @notice close position
     * @param _amm amm address
     * @param _quoteAssetAmountLimit quote asset amount limit in 18 digits (slippage). 0 for any slippage
     */
    function closePosition(IAmm _amm, Decimal.decimal memory _quoteAssetAmountLimit)
        external
        whenNotPaused
        nonReentrant
    {
        _requireAmm(_amm);
        _requireNonSandwich(_amm);

        address trader = _msgSender();
        PositionResp memory positionResp;
        Position memory position = getPosition(_amm, trader);

        // add scope for stack too deep error
        {
            // closing a long means taking a short
            IAmm.Dir dirOfBase = position.size.toInt() > 0
                ? IAmm.Dir.ADD_TO_AMM
                : IAmm.Dir.REMOVE_FROM_AMM;

            IAmm.Ratios memory ratios = _amm.getRatios();

            // if trade goes over fluctuation limit, then partial close, else full close
            if (
                _amm.isOverFluctuationLimit(dirOfBase, position.size.abs()) &&
                ratios.partialLiquidationRatio.toUint() != 0
            ) {
                positionResp = _internalPartialClose(
                    _amm,
                    trader,
                    ratios.partialLiquidationRatio,
                    Decimal.zero()
                );
            } else {
                positionResp = _internalClosePosition(_amm, trader, _quoteAssetAmountLimit);
            }

            require(positionResp.badDebt.toUint() == 0, "bad debt");

            // transfer the token from trader and vault
            IERC20 quoteToken = _amm.quoteAsset();
            _withdraw(quoteToken, trader, positionResp.marginToVault.abs());
        }

        // fees
        Decimal.decimal memory fees = _transferFees(
            trader,
            _amm,
            positionResp.exchangedQuoteAssetAmount,
            position.size.toInt() > 0 ? Side.SELL : Side.BUY
        );

        // emit event
        uint256 markPrice = _amm.getMarkPrice().toUint();
        int256 fundingPayment = positionResp.fundingPayment.toInt();
        emit PositionChanged(
            trader,
            address(_amm),
            positionResp.position.margin.toUint(),
            positionResp.exchangedQuoteAssetAmount.toUint(),
            positionResp.exchangedPositionSize.toInt(),
            fees.toUint(),
            positionResp.position.size.toInt(),
            positionResp.realizedPnl.toInt(),
            positionResp.unrealizedPnlAfter.toInt(),
            positionResp.badDebt.toUint(),
            0,
            markPrice,
            fundingPayment
        );
    }

    /**
     * @notice partially close position
     * @param _amm amm address
     * @param _partialCloseRatio % to close
     * @param _quoteAssetAmountLimit quote asset amount limit in 18 digits (slippage). 0 for any slippage
     */
    function partialClose(
        IAmm _amm,
        Decimal.decimal memory _partialCloseRatio,
        Decimal.decimal memory _quoteAssetAmountLimit
    ) external whenNotPaused nonReentrant {
        _requireAmm(_amm);
        _requireNonZeroInput(_partialCloseRatio);
        require(_partialCloseRatio.cmp(Decimal.one()) < 0, "not partial close");
        _requireNonSandwich(_amm);

        address trader = _msgSender();
        Position memory position = getPosition(_amm, trader);
        SignedDecimal.signedDecimal memory sizeToClose = position.size.mulD(_partialCloseRatio);

        // if partial close causes price to go over fluctuation limit, trim down to partial liq ratio
        Decimal.decimal memory partialLiquidationRatio = _amm.getRatios().partialLiquidationRatio;
        if (
            _amm.isOverFluctuationLimit(
                position.size.toInt() > 0 ? IAmm.Dir.ADD_TO_AMM : IAmm.Dir.REMOVE_FROM_AMM,
                sizeToClose.abs()
            ) &&
            partialLiquidationRatio.toUint() != 0 &&
            _partialCloseRatio.cmp(partialLiquidationRatio) > 0
        ) {
            _partialCloseRatio = partialLiquidationRatio;
        }

        PositionResp memory positionResp = _internalPartialClose(
            _amm,
            trader,
            _partialCloseRatio,
            _quoteAssetAmountLimit
        );

        // update position
        setPosition(_amm, trader, positionResp.position);

        require(positionResp.badDebt.toUint() == 0, "bad debt");

        // transfer the token from trader and vault
        IERC20 quoteToken = _amm.quoteAsset();
        _withdraw(quoteToken, trader, positionResp.marginToVault.abs());

        // fees
        Decimal.decimal memory fees = _transferFees(
            trader,
            _amm,
            positionResp.exchangedQuoteAssetAmount,
            position.size.toInt() > 0 ? Side.SELL : Side.BUY
        );

        // emit event
        uint256 markPrice = _amm.getMarkPrice().toUint();
        int256 fundingPayment = positionResp.fundingPayment.toInt();

        emit PositionChanged(
            trader,
            address(_amm),
            positionResp.position.margin.toUint(),
            positionResp.exchangedQuoteAssetAmount.toUint(),
            positionResp.exchangedPositionSize.toInt(),
            fees.toUint(),
            positionResp.position.size.toInt(),
            positionResp.realizedPnl.toInt(),
            positionResp.unrealizedPnlAfter.toInt(),
            positionResp.badDebt.toUint(),
            0,
            markPrice,
            fundingPayment
        );
    }

    /**
     * @notice add margin to increase margin ratio
     * @param _amm amm address
     * @param _addedMargin added margin in 18 digits
     */
    function addMargin(IAmm _amm, Decimal.decimal calldata _addedMargin)
        external
        whenNotPaused
        nonReentrant
    {
        _requireAmm(_amm);
        _requireNonZeroInput(_addedMargin);

        address trader = _msgSender();
        Position memory position = getPosition(_amm, trader);
        // update margin
        position.margin = position.margin.addD(_addedMargin);

        setPosition(_amm, trader, position);
        // transfer token from trader
        IERC20 quoteToken = _amm.quoteAsset();
        _transferFrom(quoteToken, trader, address(this), _addedMargin);
        emit MarginChanged(trader, address(_amm), int256(_addedMargin.toUint()), 0);
    }

    /**
     * @notice remove margin to decrease margin ratio
     * @param _amm amm address
     * @param _removedMargin removed margin in 18 digits
     */
    function removeMargin(IAmm _amm, Decimal.decimal calldata _removedMargin)
        external
        whenNotPaused
        nonReentrant
    {
        _requireAmm(_amm);
        _requireNonZeroInput(_removedMargin);

        address trader = _msgSender();
        // realize funding payment if there's no bad debt
        Position memory position = getPosition(_amm, trader);

        // update margin and cumulativePremiumFraction
        SignedDecimal.signedDecimal memory marginDelta = MixedDecimal
            .fromDecimal(_removedMargin)
            .mulScalar(-1);
        CalcRemainMarginReturnParams
            memory calcRemainMarginReturnParams = _calcRemainMarginWithFundingPayment(
                _amm,
                position,
                marginDelta
            );
        require(calcRemainMarginReturnParams.badDebt.toUint() == 0, "bad debt");

        position.margin = calcRemainMarginReturnParams.remainingMargin;
        position.lastUpdatedCumulativePremiumFractionLong = calcRemainMarginReturnParams
            .latestCumulativePremiumFractionLong;
        position.lastUpdatedCumulativePremiumFractionShort = calcRemainMarginReturnParams
            .latestCumulativePremiumFractionShort;

        // check enough margin
        // Use a more conservative way to restrict traders to remove their margin
        // We don't allow unrealized PnL to support their margin removal
        require(
            _calcFreeCollateral(_amm, trader, calcRemainMarginReturnParams.remainingMargin)
                .toInt() >= 0,
            "free collateral is not enough"
        );

        // update position
        setPosition(_amm, trader, position);

        // transfer token back to trader
        IERC20 quoteToken = _amm.quoteAsset();
        _withdraw(quoteToken, trader, _removedMargin);
        emit MarginChanged(
            trader,
            address(_amm),
            marginDelta.toInt(),
            calcRemainMarginReturnParams.fundingPayment.toInt()
        );
    }

    /**
     * @notice liquidate trader's underwater position. Require trader's margin ratio less than maintenance margin ratio
     * @param _amm amm address
     * @param _trader trader address
     */
    function liquidate(IAmm _amm, address _trader) external nonReentrant {
        _internalLiquidate(_amm, _trader);
    }

    /**
     * @notice settle funding payment
     * @dev dynamic funding mechanism refer (https://nftperp.notion.site/Technical-Stuff-8e4cb30f08b94aa2a576097a5008df24)
     * @param _amm amm address
     */
    function settleFunding(IAmm _amm) external whenNotPaused {
        _requireAmm(_amm);

        (
            SignedDecimal.signedDecimal memory premiumFraction,
            Decimal.decimal memory markPrice,
            Decimal.decimal memory indexPrice
        ) = _amm.settleFunding();

        /**
         * implement dynamic funding
         * premium fraction long = premium fraction * (√(PSL * PSS) / PSL)
         * premium fraction short = premium fraction * (√(PSL * PSS) / PSS)
         * funding rate longs = long premium / index
         * funding rate shorts = short premium / index
         */

        TotalPositionSize memory tps = totalPositionSizeMap[address(_amm)];
        Decimal.decimal memory squaredPositionSizeProduct = tps
            .positionSizeLong
            .mulD(tps.positionSizeShort)
            .sqrt();

        SignedDecimal.signedDecimal memory premiumFractionLong;
        SignedDecimal.signedDecimal memory premiumFractionShort;
        SignedDecimal.signedDecimal memory insuranceFundPnl;

        // if PSL or PSL is zero, use regular funding
        if (squaredPositionSizeProduct.toUint() == 0) {
            premiumFractionLong = premiumFraction;
            premiumFractionShort = premiumFraction;
            insuranceFundPnl = tps.netPositionSize.mulD(premiumFraction);
        } else {
            premiumFractionLong = premiumFraction.mulD(
                squaredPositionSizeProduct.divD(tps.positionSizeLong)
            );
            premiumFractionShort = premiumFraction.mulD(
                squaredPositionSizeProduct.divD(tps.positionSizeShort)
            );
        }

        SignedDecimal.signedDecimal memory fundingRateLong = premiumFractionLong.divD(indexPrice);
        SignedDecimal.signedDecimal memory fundingRateShort = premiumFractionShort.divD(indexPrice);
        Decimal.decimal memory fundingRateDeltaAbs = fundingRateLong.subD(fundingRateShort).abs();

        // capped dynamic funding, funding rate of a side is capped if it is more than fundingRateDeltaCapRatio
        if (fundingRateDeltaAbs.cmp(fundingRateDeltaCapRatio) <= 0) {
            // no capping
            _amm.updateFundingRate(premiumFractionLong, premiumFractionShort, indexPrice);
        } else {
            // capping
            Decimal.decimal memory x = fundingRateDeltaCapRatio.mulD(indexPrice); /** @aster2709: not sure what to call this :p  */

            if (premiumFraction.toInt() > 0) {
                // longs pay shorts
                if (premiumFractionLong.toInt() > premiumFractionShort.toInt()) {
                    // cap long losses, insurnace fund covers beyond cap
                    SignedDecimal.signedDecimal memory newPremiumFractionLong = premiumFractionShort
                        .addD(x);
                    SignedDecimal.signedDecimal memory coveredPremium = premiumFractionLong.subD(
                        newPremiumFractionLong
                    );
                    insuranceFundPnl = coveredPremium.mulD(tps.positionSizeLong).mulScalar(-1);
                    premiumFractionLong = newPremiumFractionLong;
                } else {
                    // cap short profits, insurance fund benefits beyond cap
                    SignedDecimal.signedDecimal memory newPremiumFractionShort = premiumFractionLong
                        .addD(x);
                    SignedDecimal.signedDecimal memory coveredPremium = premiumFractionShort.subD(
                        newPremiumFractionShort
                    );
                    insuranceFundPnl = coveredPremium.mulD(tps.positionSizeShort);
                    premiumFractionShort = newPremiumFractionShort;
                }
            } else {
                // shorts pay longs
                if (premiumFractionLong.toInt() < premiumFractionShort.toInt()) {
                    // cap long profits, insurnace fund benefits beyond cap
                    SignedDecimal.signedDecimal memory newPremiumFractionLong = premiumFractionShort
                        .subD(x);
                    SignedDecimal.signedDecimal memory coveredPremium = premiumFractionLong.subD(
                        newPremiumFractionLong
                    );
                    insuranceFundPnl = coveredPremium.mulD(tps.positionSizeLong).mulScalar(-1);
                } else {
                    // cap short losses, insurnace fund covers beyond cap
                    SignedDecimal.signedDecimal memory newPremiumFractionShort = premiumFractionLong
                        .subD(x);
                    SignedDecimal.signedDecimal memory coveredPremium = premiumFractionShort.subD(
                        newPremiumFractionShort
                    );
                    insuranceFundPnl = coveredPremium.mulD(tps.positionSizeShort);
                    premiumFractionShort = newPremiumFractionShort;
                }
            }
            _amm.updateFundingRate(premiumFractionLong, premiumFractionShort, indexPrice);
        }

        // update cumulative premium fractions
        (
            SignedDecimal.signedDecimal memory latestCumulativePremiumFractionLong,
            SignedDecimal.signedDecimal memory latestCumulativePremiumFractionShort
        ) = getLatestCumulativePremiumFraction(_amm);
        cumulativePremiumFractionLong[address(_amm)].push(
            premiumFractionLong.addD(latestCumulativePremiumFractionLong)
        );
        cumulativePremiumFractionShort[address(_amm)].push(
            premiumFractionShort.addD(latestCumulativePremiumFractionShort)
        );

        // settle insurance fund pnl
        IERC20 quoteToken = _amm.quoteAsset();
        if (insuranceFundPnl.toInt() > 0) {
            _transferToInsuranceFund(quoteToken, insuranceFundPnl.abs());
        } else if (insuranceFundPnl.toInt() < 0) {
            insuranceFund.withdraw(quoteToken, insuranceFundPnl.abs());
        }
        emit FundingPayment(
            address(_amm),
            markPrice.toUint(),
            indexPrice.toUint(),
            premiumFractionLong.toInt(),
            premiumFractionShort.toInt(),
            insuranceFundPnl.toInt()
        );
    }

    /**
     * @notice repeg mark price to index price
     * @dev only repeg bot can call
     * @param _amm amm address
     */
    function repegPrice(IAmm _amm) external onlyRepegBot(_amm) {
        (
            Decimal.decimal memory quoteAssetBefore,
            Decimal.decimal memory baseAssetBefore,
            Decimal.decimal memory quoteAssetAfter,
            Decimal.decimal memory baseAssetAfter,
            SignedDecimal.signedDecimal memory repegPnl
        ) = _amm.repegPrice();
        Decimal.decimal memory repegDebt = _settleRepegPnl(_amm, repegPnl);

        emit Repeg(
            address(_amm),
            quoteAssetBefore.toUint(),
            baseAssetBefore.toUint(),
            quoteAssetAfter.toUint(),
            baseAssetAfter.toUint(),
            repegPnl.toInt(),
            repegDebt.toUint()
        );
    }

    function repegLiquidityDepth(IAmm _amm, Decimal.decimal memory _multiplier)
        external
        onlyRepegBot(_amm)
    {
        (
            Decimal.decimal memory quoteAssetBefore,
            Decimal.decimal memory baseAssetBefore,
            Decimal.decimal memory quoteAssetAfter,
            Decimal.decimal memory baseAssetAfter,
            SignedDecimal.signedDecimal memory repegPnl
        ) = _amm.repegK(_multiplier);
        Decimal.decimal memory repegDebt = _settleRepegPnl(_amm, repegPnl);

        emit Repeg(
            address(_amm),
            quoteAssetBefore.toUint(),
            baseAssetBefore.toUint(),
            quoteAssetAfter.toUint(),
            baseAssetAfter.toUint(),
            repegPnl.toInt(),
            repegDebt.toUint()
        );
    }

    /**
     * @notice set repeg bot
     * @dev only owner
     * @param _amm amm address
     * @param _repegBot bot address to be set
     */
    function setRepegBot(address _amm, address _repegBot) external onlyOwner {
        repegBots[_amm] = _repegBot;
        emit RepegBotSet(_amm, _repegBot);
    }

    //
    // PUBLIC
    //

    /**
     * @notice get personal position information
     * @param _amm IAmm address
     * @param _trader trader address
     * @return struct Position
     */
    function getPosition(IAmm _amm, address _trader) public view returns (Position memory) {
        return positionMap[address(_amm)][_trader];
    }

    /**
     * @notice get margin ratio, marginRatio = (margin + funding payment + unrealized Pnl) / positionNotional
     * @param _amm amm address
     * @param _trader trader address
     * @return margin ratio in 18 digits
     */
    function getMarginRatio(IAmm _amm, address _trader)
        public
        view
        returns (SignedDecimal.signedDecimal memory)
    {
        Position memory position = getPosition(_amm, _trader);
        _requirePositionSize(position.size);
        (
            Decimal.decimal memory positionNotional,
            SignedDecimal.signedDecimal memory unrealizedPnl
        ) = getPositionNotionalAndUnrealizedPnl(_amm, _trader);
        return _getMarginRatio(_amm, position, unrealizedPnl, positionNotional);
    }

    /**
     * @notice get position notional and unrealized Pnl without fee expense and funding payment
     * @param _amm amm address
     * @param _trader trader address
     * @return positionNotional position notional
     * @return unrealizedPnl unrealized Pnl
     */
    function getPositionNotionalAndUnrealizedPnl(IAmm _amm, address _trader)
        public
        view
        returns (
            Decimal.decimal memory positionNotional,
            SignedDecimal.signedDecimal memory unrealizedPnl
        )
    {
        Position memory position = getPosition(_amm, _trader);
        Decimal.decimal memory positionSizeAbs = position.size.abs();
        if (positionSizeAbs.toUint() != 0) {
            bool isShortPosition = position.size.toInt() < 0;
            IAmm.Dir dir = isShortPosition ? IAmm.Dir.REMOVE_FROM_AMM : IAmm.Dir.ADD_TO_AMM;
            positionNotional = _amm.getOutputPrice(dir, positionSizeAbs);
            // unrealizedPnlForLongPosition = positionNotional - openNotional
            // unrealizedPnlForShortPosition = positionNotionalWhenBorrowed - positionNotionalWhenReturned =
            // openNotional - positionNotional = unrealizedPnlForLongPosition * -1
            unrealizedPnl = isShortPosition
                ? MixedDecimal.fromDecimal(position.openNotional).subD(positionNotional)
                : MixedDecimal.fromDecimal(positionNotional).subD(position.openNotional);
        }
    }

    /**
     * @notice get latest cumulative premium fraction.
     * @param _amm IAmm address
     * @return latestCumulativePremiumFractionLong cumulative premium fraction long
     * @return latestCumulativePremiumFractionShort cumulative premium fraction short
     */
    function getLatestCumulativePremiumFraction(IAmm _amm)
        public
        view
        returns (
            SignedDecimal.signedDecimal memory latestCumulativePremiumFractionLong,
            SignedDecimal.signedDecimal memory latestCumulativePremiumFractionShort
        )
    {
        address amm = address(_amm);
        uint256 lenLong = cumulativePremiumFractionLong[amm].length;
        uint256 lenShort = cumulativePremiumFractionShort[amm].length;
        if (lenLong > 0) {
            latestCumulativePremiumFractionLong = cumulativePremiumFractionLong[amm][lenLong - 1];
        }
        if (lenShort > 0) {
            latestCumulativePremiumFractionShort = cumulativePremiumFractionShort[amm][
                lenShort - 1
            ];
        }
    }

    //
    // INTERNAL
    //

    function _getMarginRatio(
        IAmm _amm,
        Position memory _position,
        SignedDecimal.signedDecimal memory _unrealizedPnl,
        Decimal.decimal memory _positionNotional
    ) internal view returns (SignedDecimal.signedDecimal memory) {
        CalcRemainMarginReturnParams
            memory calcRemainMarginReturnParams = _calcRemainMarginWithFundingPayment(
                _amm,
                _position,
                _unrealizedPnl
            );
        return
            MixedDecimal
                .fromDecimal(calcRemainMarginReturnParams.remainingMargin)
                .subD(calcRemainMarginReturnParams.badDebt)
                .divD(_positionNotional);
    }

    // only called from openPosition and _closeAndOpenReversePosition. calling fn needs to ensure there's enough marginRatio
    function _internalIncreasePosition(
        IAmm _amm,
        Side _side,
        Decimal.decimal memory _openNotional,
        Decimal.decimal memory _minPositionSize,
        Decimal.decimal memory _leverage
    ) internal returns (PositionResp memory positionResp) {
        address trader = _msgSender();
        Position memory oldPosition = getPosition(_amm, trader);
        positionResp.exchangedPositionSize = _swapInput(
            _amm,
            _side,
            _openNotional,
            _minPositionSize,
            false
        );
        SignedDecimal.signedDecimal memory newSize = oldPosition.size.addD(
            positionResp.exchangedPositionSize
        );

        _updateOpenInterestNotional(_amm, MixedDecimal.fromDecimal(_openNotional));
        _updateTotalPositionSize(_amm, positionResp.exchangedPositionSize, _side);

        Decimal.decimal memory maxHoldingBaseAsset = _amm.getMaxHoldingBaseAsset();
        if (maxHoldingBaseAsset.toUint() != 0) {
            // total position size should be less than `positionUpperBound`
            require(newSize.abs().cmp(maxHoldingBaseAsset) <= 0, "positionSize cap");
        }

        SignedDecimal.signedDecimal memory marginToAdd = MixedDecimal.fromDecimal(
            _openNotional.divD(_leverage)
        );
        CalcRemainMarginReturnParams
            memory calcRemainMarginReturnParams = _calcRemainMarginWithFundingPayment(
                _amm,
                oldPosition,
                marginToAdd
            );

        (, SignedDecimal.signedDecimal memory unrealizedPnl) = getPositionNotionalAndUnrealizedPnl(
            _amm,
            trader
        );

        // update positionResp
        positionResp.exchangedQuoteAssetAmount = _openNotional;
        positionResp.unrealizedPnlAfter = unrealizedPnl;
        positionResp.marginToVault = marginToAdd;
        positionResp.fundingPayment = calcRemainMarginReturnParams.fundingPayment;
        positionResp.position = Position(
            newSize,
            calcRemainMarginReturnParams.remainingMargin,
            oldPosition.openNotional.addD(positionResp.exchangedQuoteAssetAmount),
            calcRemainMarginReturnParams.latestCumulativePremiumFractionLong,
            calcRemainMarginReturnParams.latestCumulativePremiumFractionShort,
            block.number
        );
    }

    function _openReversePosition(
        IAmm _amm,
        Side _side,
        address _trader,
        Decimal.decimal memory _quoteAssetAmount,
        Decimal.decimal memory _leverage,
        Decimal.decimal memory _baseAssetAmountLimit,
        bool _canOverFluctuationLimit
    ) internal returns (PositionResp memory) {
        Decimal.decimal memory openNotional = _quoteAssetAmount.mulD(_leverage);
        (
            Decimal.decimal memory oldPositionNotional,
            SignedDecimal.signedDecimal memory unrealizedPnl
        ) = getPositionNotionalAndUnrealizedPnl(_amm, _trader);
        PositionResp memory positionResp;

        // reduce position if old position is larger
        if (oldPositionNotional.toUint() > openNotional.toUint()) {
            // for reducing oi and tps from respective side

            Position memory oldPosition = getPosition(_amm, _trader);
            {
                positionResp.exchangedPositionSize = _swapInput(
                    _amm,
                    _side,
                    openNotional,
                    _baseAssetAmountLimit,
                    _canOverFluctuationLimit
                );

                // realizedPnl = unrealizedPnl * closedRatio
                // closedRatio = positionResp.exchangedPositionSize / oldPosition.size
                if (oldPosition.size.toInt() != 0) {
                    positionResp.realizedPnl = unrealizedPnl
                        .mulD(positionResp.exchangedPositionSize.abs())
                        .divD(oldPosition.size.abs());
                }

                CalcRemainMarginReturnParams
                    memory calcRemainMarginReturnParams = _calcRemainMarginWithFundingPayment(
                        _amm,
                        oldPosition,
                        positionResp.realizedPnl
                    );

                // positionResp.unrealizedPnlAfter = unrealizedPnl - realizedPnl
                positionResp.unrealizedPnlAfter = unrealizedPnl.subD(positionResp.realizedPnl);
                positionResp.exchangedQuoteAssetAmount = openNotional;

                // calculate openNotional (it's different depends on long or short side)
                // long: unrealizedPnl = positionNotional - openNotional => openNotional = positionNotional - unrealizedPnl
                // short: unrealizedPnl = openNotional - positionNotional => openNotional = positionNotional + unrealizedPnl
                // positionNotional = oldPositionNotional - exchangedQuoteAssetAmount
                SignedDecimal.signedDecimal memory remainOpenNotional = oldPosition.size.toInt() > 0
                    ? MixedDecimal
                        .fromDecimal(oldPositionNotional)
                        .subD(positionResp.exchangedQuoteAssetAmount)
                        .subD(positionResp.unrealizedPnlAfter)
                    : positionResp.unrealizedPnlAfter.addD(oldPositionNotional).subD(
                        positionResp.exchangedQuoteAssetAmount
                    );
                require(remainOpenNotional.toInt() > 0, "remainNotional <= 0");

                positionResp.position = Position(
                    oldPosition.size.addD(positionResp.exchangedPositionSize),
                    calcRemainMarginReturnParams.remainingMargin,
                    remainOpenNotional.abs(),
                    calcRemainMarginReturnParams.latestCumulativePremiumFractionLong,
                    calcRemainMarginReturnParams.latestCumulativePremiumFractionShort,
                    block.number
                );
            }

            // update open interest and total position sizes
            Side side = _side == Side.BUY ? Side.BUY : Side.SELL; // reduce
            _updateTotalPositionSize(_amm, positionResp.exchangedPositionSize, side);
            _updateOpenInterestNotional(
                _amm,
                positionResp
                .realizedPnl
                .addD(positionResp.badDebt) // bad debt also considers as removed notional
                    .addD(oldPosition.openNotional)
                    .subD(positionResp.position.openNotional)
                    .mulScalar(-1)
            );
            return positionResp;
        }
        return
            _closeAndOpenReversePosition(
                _amm,
                _side,
                _trader,
                _quoteAssetAmount,
                _leverage,
                _baseAssetAmountLimit
            );
    }

    function _closeAndOpenReversePosition(
        IAmm _amm,
        Side _side,
        address _trader,
        Decimal.decimal memory _quoteAssetAmount,
        Decimal.decimal memory _leverage,
        Decimal.decimal memory _baseAssetAmountLimit
    ) internal returns (PositionResp memory positionResp) {
        // new position size is larger than or equal to the old position size
        // so either close or close then open a larger position
        PositionResp memory closePositionResp = _internalClosePosition(
            _amm,
            _trader,
            Decimal.zero()
        );

        // the old position is underwater. trader should close a position first
        require(closePositionResp.badDebt.toUint() == 0, "bad debt");

        // update open notional after closing position
        Decimal.decimal memory openNotional = _quoteAssetAmount.mulD(_leverage).subD(
            closePositionResp.exchangedQuoteAssetAmount
        );

        // if remain exchangedQuoteAssetAmount is too small (eg. 1wei) then the required margin might be 0
        // then the clearingHouse will stop opening position
        if (openNotional.divD(_leverage).toUint() == 0) {
            positionResp = closePositionResp;
        } else {
            Decimal.decimal memory updatedBaseAssetAmountLimit;
            if (_baseAssetAmountLimit.toUint() > closePositionResp.exchangedPositionSize.toUint()) {
                updatedBaseAssetAmountLimit = _baseAssetAmountLimit.subD(
                    closePositionResp.exchangedPositionSize.abs()
                );
            }

            PositionResp memory increasePositionResp = _internalIncreasePosition(
                _amm,
                _side,
                openNotional,
                updatedBaseAssetAmountLimit,
                _leverage
            );
            positionResp = PositionResp({
                position: increasePositionResp.position,
                exchangedQuoteAssetAmount: closePositionResp.exchangedQuoteAssetAmount.addD(
                    increasePositionResp.exchangedQuoteAssetAmount
                ),
                badDebt: closePositionResp.badDebt.addD(increasePositionResp.badDebt),
                fundingPayment: closePositionResp.fundingPayment.addD(
                    increasePositionResp.fundingPayment
                ),
                exchangedPositionSize: closePositionResp.exchangedPositionSize.addD(
                    increasePositionResp.exchangedPositionSize
                ),
                realizedPnl: closePositionResp.realizedPnl.addD(increasePositionResp.realizedPnl),
                unrealizedPnlAfter: SignedDecimal.zero(),
                marginToVault: closePositionResp.marginToVault.addD(
                    increasePositionResp.marginToVault
                )
            });
        }
        return positionResp;
    }

    function _internalClosePosition(
        IAmm _amm,
        address _trader,
        Decimal.decimal memory _quoteAssetAmountLimit
    ) internal returns (PositionResp memory positionResp) {
        // check conditions
        Position memory oldPosition = getPosition(_amm, _trader);
        _requirePositionSize(oldPosition.size);

        (, SignedDecimal.signedDecimal memory unrealizedPnl) = getPositionNotionalAndUnrealizedPnl(
            _amm,
            _trader
        );
        CalcRemainMarginReturnParams
            memory calcRemainMarginReturnParams = _calcRemainMarginWithFundingPayment(
                _amm,
                oldPosition,
                unrealizedPnl
            );

        positionResp.exchangedPositionSize = oldPosition.size.mulScalar(-1);
        positionResp.realizedPnl = unrealizedPnl;
        positionResp.badDebt = calcRemainMarginReturnParams.badDebt;
        positionResp.fundingPayment = calcRemainMarginReturnParams.fundingPayment;
        positionResp.marginToVault = MixedDecimal
            .fromDecimal(calcRemainMarginReturnParams.remainingMargin)
            .mulScalar(-1);

        // for amm.swapOutput, the direction is in base asset, from the perspective of Amm
        positionResp.exchangedQuoteAssetAmount = _amm.swapOutput(
            oldPosition.size.toInt() > 0 ? IAmm.Dir.ADD_TO_AMM : IAmm.Dir.REMOVE_FROM_AMM,
            oldPosition.size.abs(),
            _quoteAssetAmountLimit
        );

        Side side = oldPosition.size.toInt() > 0 ? Side.BUY : Side.SELL;
        // bankrupt position's bad debt will be also consider as a part of the open interest
        _updateOpenInterestNotional(
            _amm,
            unrealizedPnl
                .addD(calcRemainMarginReturnParams.badDebt)
                .addD(oldPosition.openNotional)
                .mulScalar(-1)
        );
        _updateTotalPositionSize(_amm, positionResp.exchangedPositionSize, side);
        _clearPosition(_amm, _trader);
    }

    function _internalPartialClose(
        IAmm _amm,
        address _trader,
        Decimal.decimal memory _partialCloseRatio,
        Decimal.decimal memory _quoteAssetAmountLimit
    ) internal returns (PositionResp memory) {
        // check conditions
        Position memory oldPosition = getPosition(_amm, _trader);
        _requirePositionSize(oldPosition.size);

        (
            Decimal.decimal memory oldPositionNotional,
            SignedDecimal.signedDecimal memory unrealizedPnl
        ) = getPositionNotionalAndUnrealizedPnl(_amm, _trader);

        SignedDecimal.signedDecimal memory sizeToClose = oldPosition.size.mulD(_partialCloseRatio);
        SignedDecimal.signedDecimal memory marginToRemove = MixedDecimal.fromDecimal(
            oldPosition.margin.mulD(_partialCloseRatio)
        );

        PositionResp memory positionResp;
        CalcRemainMarginReturnParams memory calcRemaingMarginReturnParams;
        // scope for avoiding stack too deep error
        {
            positionResp.exchangedPositionSize = sizeToClose.mulScalar(-1);

            positionResp.realizedPnl = unrealizedPnl.mulD(_partialCloseRatio);
            positionResp.unrealizedPnlAfter = unrealizedPnl.subD(positionResp.realizedPnl);

            calcRemaingMarginReturnParams = _calcRemainMarginWithFundingPayment(
                _amm,
                oldPosition,
                marginToRemove.mulScalar(-1)
            );
            positionResp.badDebt = calcRemaingMarginReturnParams.badDebt;
            positionResp.fundingPayment = calcRemaingMarginReturnParams.fundingPayment;
            positionResp.marginToVault = marginToRemove.addD(positionResp.realizedPnl).mulScalar(
                -1
            );

            // for amm.swapOutput, the direction is in base asset, from the perspective of Amm
            positionResp.exchangedQuoteAssetAmount = _amm.swapOutput(
                oldPosition.size.toInt() > 0 ? IAmm.Dir.ADD_TO_AMM : IAmm.Dir.REMOVE_FROM_AMM,
                sizeToClose.abs(),
                _quoteAssetAmountLimit
            );
        }

        SignedDecimal.signedDecimal memory remainOpenNotional = oldPosition.size.toInt() > 0
            ? MixedDecimal
                .fromDecimal(oldPositionNotional)
                .subD(positionResp.exchangedQuoteAssetAmount)
                .subD(positionResp.unrealizedPnlAfter)
            : positionResp.unrealizedPnlAfter.addD(oldPositionNotional).subD(
                positionResp.exchangedQuoteAssetAmount
            );
        require(remainOpenNotional.toInt() > 0, "value of openNotional <= 0");

        positionResp.position = Position(
            oldPosition.size.subD(sizeToClose),
            calcRemaingMarginReturnParams.remainingMargin,
            remainOpenNotional.abs(),
            calcRemaingMarginReturnParams.latestCumulativePremiumFractionLong,
            calcRemaingMarginReturnParams.latestCumulativePremiumFractionShort,
            block.number
        );

        // for reducing oi and tps from respective side
        Side side = oldPosition.size.toInt() > 0 ? Side.BUY : Side.SELL;
        _updateOpenInterestNotional(
            _amm,
            positionResp
            .realizedPnl
            .addD(positionResp.badDebt) // bad debt also considers as removed notional
                .addD(oldPosition.openNotional)
                .subD(positionResp.position.openNotional)
                .mulScalar(-1)
        );
        _updateTotalPositionSize(_amm, positionResp.exchangedPositionSize, side);

        return positionResp;
    }

    function _internalLiquidate(IAmm _amm, address _trader)
        internal
        returns (Decimal.decimal memory quoteAssetAmount, bool isPartialClose)
    {
        _requireAmm(_amm);

        SignedDecimal.signedDecimal memory marginRatio = getMarginRatio(_amm, _trader);
        IAmm.Ratios memory ratios = _amm.getRatios();
        _requireMoreMarginRatio(marginRatio, ratios.maintenanceMarginRatio, false);

        PositionResp memory positionResp;
        Decimal.decimal memory liquidationPenalty;
        {
            Decimal.decimal memory liquidationBadDebt;
            Decimal.decimal memory feeToLiquidator;
            Decimal.decimal memory feeToInsuranceFund;
            IERC20 quoteAsset = _amm.quoteAsset();

            // partially liquidate if over liquidation fee ratio
            if (
                marginRatio.toInt() > int256(ratios.liquidationFeeRatio.toUint()) &&
                ratios.partialLiquidationRatio.toUint() != 0
            ) {
                Position memory position = getPosition(_amm, _trader);

                Decimal.decimal memory partiallyLiquidatedPositionNotional = _amm.getOutputPrice(
                    position.size.toInt() > 0 ? IAmm.Dir.ADD_TO_AMM : IAmm.Dir.REMOVE_FROM_AMM,
                    position.size.mulD(ratios.partialLiquidationRatio).abs()
                );

                positionResp = _openReversePosition(
                    _amm,
                    position.size.toInt() > 0 ? Side.SELL : Side.BUY,
                    _trader,
                    partiallyLiquidatedPositionNotional,
                    Decimal.one(),
                    Decimal.zero(),
                    true
                );

                // half of the liquidationFee goes to liquidator & another half goes to insurance fund
                liquidationPenalty = positionResp.exchangedQuoteAssetAmount.mulD(
                    ratios.liquidationFeeRatio
                );
                feeToLiquidator = liquidationPenalty.divScalar(2);
                feeToInsuranceFund = liquidationPenalty.subD(feeToLiquidator);

                positionResp.position.margin = positionResp.position.margin.subD(
                    liquidationPenalty
                );

                // update position
                setPosition(_amm, _trader, positionResp.position);

                isPartialClose = true;
            } else {
                positionResp = _internalClosePosition(_amm, _trader, Decimal.zero());

                Decimal.decimal memory remainingMargin = positionResp.marginToVault.abs();

                feeToLiquidator = positionResp
                    .exchangedQuoteAssetAmount
                    .mulD(ratios.liquidationFeeRatio)
                    .divScalar(2);

                if (feeToLiquidator.toUint() > remainingMargin.toUint()) {
                    liquidationBadDebt = feeToLiquidator.subD(remainingMargin);
                } else {
                    feeToInsuranceFund = remainingMargin.subD(feeToLiquidator);
                }

                liquidationPenalty = feeToLiquidator.addD(feeToInsuranceFund);
            }

            if (feeToInsuranceFund.toUint() > 0) {
                _transferToInsuranceFund(quoteAsset, feeToInsuranceFund);
            }
            // reward liquidator
            _withdraw(quoteAsset, _msgSender(), feeToLiquidator);

            emit PositionLiquidated(
                _trader,
                address(_amm),
                _msgSender(),
                positionResp.exchangedQuoteAssetAmount.toUint(),
                positionResp.exchangedPositionSize.toUint(),
                feeToLiquidator.toUint(),
                feeToInsuranceFund.toUint(),
                liquidationBadDebt.toUint()
            );
        }

        // emit event
        uint256 markPrice = _amm.getMarkPrice().toUint();
        int256 fundingPayment = positionResp.fundingPayment.toInt();
        emit PositionChanged(
            _trader,
            address(_amm),
            positionResp.position.margin.toUint(),
            positionResp.exchangedQuoteAssetAmount.toUint(),
            positionResp.exchangedPositionSize.toInt(),
            0,
            positionResp.position.size.toInt(),
            positionResp.realizedPnl.toInt(),
            positionResp.unrealizedPnlAfter.toInt(),
            positionResp.badDebt.toUint(),
            liquidationPenalty.toUint(),
            markPrice,
            fundingPayment
        );

        return (positionResp.exchangedQuoteAssetAmount, isPartialClose);
    }

    function _swapInput(
        IAmm _amm,
        Side _side,
        Decimal.decimal memory _inputAmount,
        Decimal.decimal memory _minOutputAmount,
        bool _canOverFluctuationLimit
    ) internal returns (SignedDecimal.signedDecimal memory) {
        // for amm.swapInput, the direction is in quote asset, from the perspective of Amm
        IAmm.Dir dir = (_side == Side.BUY) ? IAmm.Dir.ADD_TO_AMM : IAmm.Dir.REMOVE_FROM_AMM;
        SignedDecimal.signedDecimal memory outputAmount = MixedDecimal.fromDecimal(
            _amm.swapInput(dir, _inputAmount, _minOutputAmount, _canOverFluctuationLimit)
        );
        if (IAmm.Dir.REMOVE_FROM_AMM == dir) {
            return outputAmount.mulScalar(-1);
        }
        return outputAmount;
    }

    function _transferFees(
        address _from,
        IAmm _amm,
        Decimal.decimal memory _positionNotional,
        Side _side
    ) internal returns (Decimal.decimal memory fees) {
        fees = _amm.calcFee(
            _side == Side.BUY ? IAmm.Dir.ADD_TO_AMM : IAmm.Dir.REMOVE_FROM_AMM,
            _positionNotional
        );

        if (fees.toUint() > 0) {
            IERC20 quoteToken = _amm.quoteAsset();
            /**
             * toll fees - fees towards clearing house
             * spread fees - fees towards insurance fund
             */
            Decimal.decimal memory tollFees = fees.divScalar(2);
            Decimal.decimal memory spreadFees = fees.subD(tollFees);

            _transferFrom(quoteToken, _from, address(this), tollFees);
            tollMap[address(quoteToken)] = tollMap[address(quoteToken)].addD(tollFees);

            _transferFrom(quoteToken, _from, address(insuranceFund), spreadFees);
        }
    }

    function _withdraw(
        IERC20 _token,
        address _receiver,
        Decimal.decimal memory _amount
    ) internal {
        // token balance (without toll fees)
        Decimal.decimal memory tollTotal = tollMap[address(_token)];
        Decimal.decimal memory totalTokenBalance = _balanceOf(_token, address(this)).subD(
            tollTotal
        );
        // if token balance is less than withdrawal amount, use toll to cover deficit
        // if toll balance is still insufficient, borrow from insurance fund
        if (totalTokenBalance.toUint() < _amount.toUint()) {
            Decimal.decimal memory balanceShortage = _amount.subD(totalTokenBalance);
            Decimal.decimal memory tollShortage = _coverWithToll(_token, balanceShortage);
            if (tollShortage.toUint() > 0) {
                insuranceFund.withdraw(_token, tollShortage);
            }
        }

        _transfer(_token, _receiver, _amount);
    }

    function _coverWithToll(IERC20 _token, Decimal.decimal memory _amount)
        internal
        returns (Decimal.decimal memory tollShortage)
    {
        Decimal.decimal memory tollTotal = tollMap[address(_token)];
        if (tollTotal.toUint() > _amount.toUint()) {
            tollMap[address(_token)] = tollTotal.subD(_amount);
        } else {
            tollShortage = _amount.subD(tollTotal);
            tollMap[address(_token)] = Decimal.zero();
        }
    }

    function _settleRepegPnl(IAmm _amm, SignedDecimal.signedDecimal memory _repegPnl)
        internal
        returns (Decimal.decimal memory repegDebt)
    {
        Decimal.decimal memory repegPnlAbs = _repegPnl.abs();
        IERC20 token = _amm.quoteAsset();
        // settle pnl with insurance fund
        if (_repegPnl.isNegative()) {
            // use toll to cover repeg loss
            // if toll is not enough, borrow deficit from insurance fund
            repegDebt = _coverWithToll(token, repegPnlAbs);
            if (repegDebt.toUint() > 0) {
                insuranceFund.withdraw(token, repegDebt);
            }
        } else {
            // transfer to insurance fund
            _transferToInsuranceFund(token, repegPnlAbs);
        }
    }

    function _transferToInsuranceFund(IERC20 _token, Decimal.decimal memory _amount) internal {
        Decimal.decimal memory totalTokenBalance = _balanceOf(_token, address(this));
        Decimal.decimal memory amountToTransfer = _amount.cmp(totalTokenBalance) > 0
            ? totalTokenBalance
            : _amount;
        _transfer(_token, address(insuranceFund), amountToTransfer);
    }

    function _updateOpenInterestNotional(IAmm _amm, SignedDecimal.signedDecimal memory _amount)
        internal
    {
        // when cap = 0 means no cap
        uint256 openInterestNotionalCap = _amm.getOpenInterestNotionalCap().toUint();
        SignedDecimal.signedDecimal memory openInterestNotional = MixedDecimal.fromDecimal(
            openInterestNotionalMap[address(_amm)]
        );
        openInterestNotional = _amount.addD(openInterestNotional);
        if (openInterestNotional.toInt() < 0) {
            openInterestNotional = SignedDecimal.zero();
        }
        if (openInterestNotionalCap != 0) {
            require(
                openInterestNotional.toUint() <= openInterestNotionalCap,
                "over open interest cap"
            );
        }

        openInterestNotionalMap[address(_amm)] = openInterestNotional.abs();
    }

    function _updateTotalPositionSize(
        IAmm _amm,
        SignedDecimal.signedDecimal memory _amount,
        Side _side
    ) internal {
        TotalPositionSize memory tps = totalPositionSizeMap[address(_amm)];
        tps.netPositionSize = _amount.addD(tps.netPositionSize);
        if (_side == Side.BUY) {
            tps.positionSizeLong = _amount.addD(tps.positionSizeLong).abs();
        } else {
            tps.positionSizeShort = _amount.mulScalar(-1).addD(tps.positionSizeShort).abs();
        }
        totalPositionSizeMap[address(_amm)] = tps;
    }

    function setPosition(
        IAmm _amm,
        address _trader,
        Position memory _position
    ) internal {
        Position storage positionStorage = positionMap[address(_amm)][_trader];
        positionStorage.size = _position.size;
        positionStorage.margin = _position.margin;
        positionStorage.openNotional = _position.openNotional;
        positionStorage.lastUpdatedCumulativePremiumFractionLong = _position
            .lastUpdatedCumulativePremiumFractionLong;
        positionStorage.lastUpdatedCumulativePremiumFractionShort = _position
            .lastUpdatedCumulativePremiumFractionShort;
        positionStorage.blockNumber = _position.blockNumber;
    }

    function _clearPosition(IAmm _amm, address _trader) internal {
        // keep the record in order to retain the last updated block number
        positionMap[address(_amm)][_trader] = Position({
            size: SignedDecimal.zero(),
            margin: Decimal.zero(),
            openNotional: Decimal.zero(),
            lastUpdatedCumulativePremiumFractionLong: SignedDecimal.zero(),
            lastUpdatedCumulativePremiumFractionShort: SignedDecimal.zero(),
            blockNumber: block.number
        });
    }

    function _calcRemainMarginWithFundingPayment(
        IAmm _amm,
        Position memory _oldPosition,
        SignedDecimal.signedDecimal memory _marginDelta
    ) internal view returns (CalcRemainMarginReturnParams memory calcRemainMarginReturnParams) {
        // calculate funding payment
        (
            calcRemainMarginReturnParams.latestCumulativePremiumFractionLong,
            calcRemainMarginReturnParams.latestCumulativePremiumFractionShort
        ) = getLatestCumulativePremiumFraction(_amm);

        if (_oldPosition.size.toInt() != 0) {
            if (_oldPosition.size.toInt() > 0) {
                calcRemainMarginReturnParams.fundingPayment = calcRemainMarginReturnParams
                    .latestCumulativePremiumFractionLong
                    .subD(_oldPosition.lastUpdatedCumulativePremiumFractionLong)
                    .mulD(_oldPosition.size);
            } else {
                calcRemainMarginReturnParams.fundingPayment = calcRemainMarginReturnParams
                    .latestCumulativePremiumFractionShort
                    .subD(_oldPosition.lastUpdatedCumulativePremiumFractionShort)
                    .mulD(_oldPosition.size);
            }
        }

        // calculate remain margin
        SignedDecimal.signedDecimal memory signedRemainMargin = _marginDelta
            .subD(calcRemainMarginReturnParams.fundingPayment)
            .addD(_oldPosition.margin);

        // if remain margin is negative, set to zero and leave the rest to bad debt
        if (signedRemainMargin.toInt() < 0) {
            calcRemainMarginReturnParams.badDebt = signedRemainMargin.abs();
        } else {
            calcRemainMarginReturnParams.remainingMargin = signedRemainMargin.abs();
        }
    }

    function _calcFreeCollateral(
        IAmm _amm,
        address _trader,
        Decimal.decimal memory _marginWithFundingPayment
    ) internal view returns (SignedDecimal.signedDecimal memory) {
        Position memory pos = getPosition(_amm, _trader);
        (
            Decimal.decimal memory positionNotional,
            SignedDecimal.signedDecimal memory unrealizedPnl
        ) = getPositionNotionalAndUnrealizedPnl(_amm, _trader);

        // min(margin + funding, margin + funding + unrealized PnL) - position value * initMarginRatio
        SignedDecimal.signedDecimal memory accountValue = unrealizedPnl.addD(
            _marginWithFundingPayment
        );
        SignedDecimal.signedDecimal memory minCollateral = unrealizedPnl.toInt() > 0
            ? MixedDecimal.fromDecimal(_marginWithFundingPayment)
            : accountValue;

        // margin requirement
        // if holding a long position, using open notional
        // if holding a short position, using position notional
        Decimal.decimal memory initMarginRatio = _amm.getRatios().initMarginRatio;
        SignedDecimal.signedDecimal memory marginRequirement = pos.size.toInt() > 0
            ? MixedDecimal.fromDecimal(pos.openNotional).mulD(initMarginRatio)
            : MixedDecimal.fromDecimal(positionNotional).mulD(initMarginRatio);

        return minCollateral.subD(marginRequirement);
    }

    function _requireAmm(IAmm _amm) internal view {
        require(insuranceFund.isExistedAmm(_amm), "amm not found");
    }

    function _requireNonZeroInput(Decimal.decimal memory _decimal) internal pure {
        require(_decimal.toUint() != 0, "0 input");
    }

    function _requirePositionSize(SignedDecimal.signedDecimal memory _size) internal pure {
        require(_size.toInt() != 0, "positionSize is 0");
    }

    function _requireNonSandwich(IAmm _amm) internal view {
        uint256 currentBlock = block.number;
        require(getPosition(_amm, _msgSender()).blockNumber != currentBlock, "non sandwich");
    }

    function _requireMoreMarginRatio(
        SignedDecimal.signedDecimal memory _marginRatio,
        Decimal.decimal memory _baseMarginRatio,
        bool _largerThanOrEqualTo
    ) internal pure {
        int256 remainingMarginRatio = _marginRatio.subD(_baseMarginRatio).toInt();
        require(
            _largerThanOrEqualTo ? remainingMarginRatio >= 0 : remainingMarginRatio < 0,
            "margin ratio not meet critera"
        );
    }
}

