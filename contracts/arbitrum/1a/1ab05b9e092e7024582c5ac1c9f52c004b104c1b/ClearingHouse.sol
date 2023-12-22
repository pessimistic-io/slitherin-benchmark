// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.9;

import { BlockContext } from "./BlockContext.sol";
import { IERC20 } from "./IERC20.sol";
import { ReentrancyGuardUpgradeable } from "./ReentrancyGuardUpgradeable.sol";
import { Math } from "./Math.sol";
import { OwnerPausableUpgradeSafe } from "./OwnerPausable.sol";
import { IAmm } from "./IAmm.sol";
import { IInsuranceFund } from "./IInsuranceFund.sol";
import { IMultiTokenRewardRecipient } from "./IMultiTokenRewardRecipient.sol";
import { IntMath } from "./IntMath.sol";
import { UIntMath } from "./UIntMath.sol";
import { TransferHelper } from "./TransferHelper.sol";
import { AmmMath } from "./AmmMath.sol";
import { IClearingHouse } from "./IClearingHouse.sol";
import { IInsuranceFundCallee } from "./IInsuranceFundCallee.sol";
import { IWhitelistMaster } from "./IWhitelistMaster.sol";

contract ClearingHouse is IClearingHouse, IInsuranceFundCallee, OwnerPausableUpgradeSafe, ReentrancyGuardUpgradeable, BlockContext {
    using UIntMath for uint256;
    using IntMath for int256;
    using TransferHelper for IERC20;

    //
    // Struct and Enum
    //

    enum PnlCalcOption {
        SPOT_PRICE,
        TWAP,
        ORACLE
    }

    /// @param MAX_PNL most beneficial way for traders to calculate position notional
    /// @param MIN_PNL least beneficial way for traders to calculate position notional
    enum PnlPreferenceOption {
        MAX_PNL,
        MIN_PNL
    }

    struct InternalOpenPositionParams {
        IAmm amm;
        Side side;
        address trader;
        uint256 amount;
        uint256 leverage;
        bool isQuote;
        bool canOverFluctuationLimit;
    }

    /// @notice This struct is used for avoiding stack too deep error when passing too many var between functions
    struct PositionResp {
        Position position;
        // the quote asset amount trader will send if open position, will receive if close
        uint256 exchangedQuoteAssetAmount;
        // if realizedPnl + realizedFundingPayment + margin is negative, it's the abs value of it
        uint256 badDebt;
        // the base asset amount trader will receive if open position, will send if close
        int256 exchangedPositionSize;
        // funding payment incurred during this position response
        int256 fundingPayment;
        // realizedPnl = unrealizedPnl * closedRatio
        int256 realizedPnl;
        // positive = trader transfer margin to vault, negative = trader receive margin from vault
        // it's 0 when internalReducePosition, its addedMargin when _increasePosition
        // it's min(0, oldPosition + realizedFundingPayment + realizedPnl) when _closePosition
        int256 marginToVault;
        // unrealized pnl after open position
        int256 unrealizedPnlAfter;
        // fee to the insurance fund
        uint256 spreadFee;
        // fee to the toll pool which provides rewards to the token stakers
        uint256 tollFee;
    }

    struct AmmMap {
        // issue #1471
        // last block when it turn restriction mode on.
        // In restriction mode, no one can do multi open/close/liquidate position in the same block.
        // If any underwater position being closed (having a bad debt and make insuranceFund loss),
        // or any liquidation happened,
        // restriction mode is ON in that block and OFF(default) in the next block.
        // This design is to prevent the attacker being benefited from the multiple action in one block
        // in extreme cases
        uint256 lastRestrictionBlock;
        int256 latestCumulativePremiumFractionLong;
        int256 latestCumulativePremiumFractionShort;
        mapping(address => Position) positionMap;
    }

    // constants
    uint256 public constant LIQ_SWITCH_RATIO = 0.2 ether; // 20%

    //**********************************************************//
    //    Can not change the order of below state variables     //
    //**********************************************************//
    //string public override versionRecipient;

    // key by amm address
    mapping(address => AmmMap) internal ammMap;

    // prepaid bad debt balance, key by Amm address
    mapping(address => uint256) public prepaidBadDebts;

    // contract dependencies
    IInsuranceFund public insuranceFund;
    IMultiTokenRewardRecipient public tollPool;

    mapping(address => bool) public backstopLiquidityProviderMap;

    // vamm => balance of vault
    mapping(IAmm => uint256) public vaults;

    // amm => revenue since last funding, used for calculation of k-adjustment budget
    mapping(IAmm => int256) public netRevenuesSinceLastFunding;

    address public whitelistMaster;

    uint256[50] private __gap;

    //**********************************************************//
    //    Can not change the order of above state variables     //
    //**********************************************************//

    //◥◤◥◤◥◤◥◤◥◤◥◤◥◤◥◤ add state variables below ◥◤◥◤◥◤◥◤◥◤◥◤◥◤◥◤//

    //◢◣◢◣◢◣◢◣◢◣◢◣◢◣◢◣ add state variables above ◢◣◢◣◢◣◢◣◢◣◢◣◢◣◢◣//
    //

    //
    // EVENTS
    //
    event BackstopLiquidityProviderChanged(address indexed account, bool indexed isProvider);
    event MarginChanged(address indexed sender, address indexed amm, int256 amount, int256 fundingPayment);
    event PositionSettled(address indexed amm, address indexed trader, uint256 valueTransferred);
    event RestrictionModeEntered(address amm, uint256 blockNumber);
    event Repeg(address amm, uint256 quoteAssetReserve, uint256 baseAssetReserve, int256 cost);
    event UpdateK(address amm, uint256 quoteAssetReserve, uint256 baseAssetReserve, int256 cost);

    /// @notice This event is emitted when position change
    /// @param trader the address which execute this transaction
    /// @param amm IAmm address
    /// @param margin margin
    /// @param positionNotional margin * leverage
    /// @param exchangedPositionSize position size
    /// @param fee transaction fee
    /// @param positionSizeAfter position size after this transaction, might be increased or decreased
    /// @param realizedPnl realized pnl after this position changed
    /// @param unrealizedPnlAfter unrealized pnl after this position changed
    /// @param badDebt position change amount cleared by insurance funds
    /// @param liquidationPenalty amount of remaining margin lost due to liquidation
    /// @param spotPrice quote asset reserve / base asset reserve
    /// @param fundingPayment funding payment (+: trader paid, -: trader received)
    event PositionChanged(
        address indexed trader,
        address indexed amm,
        int256 margin,
        uint256 positionNotional,
        int256 exchangedPositionSize,
        uint256 fee,
        int256 positionSizeAfter,
        int256 realizedPnl,
        int256 unrealizedPnlAfter,
        uint256 badDebt,
        uint256 liquidationPenalty,
        uint256 spotPrice,
        int256 fundingPayment
    );

    /// @notice This event is emitted when position liquidated
    /// @param trader the account address being liquidated
    /// @param amm IAmm address
    /// @param positionNotional liquidated position value minus liquidationFee
    /// @param positionSize liquidated position size
    /// @param feeToLiquidator liquidation fee to the liquidator
    /// @param feeToInsuranceFund liquidation fee to the insurance fund
    /// @param liquidator the address which execute this transaction
    /// @param badDebt liquidation bad debt cleared by insurance funds
    event PositionLiquidated(
        address indexed trader,
        address indexed amm,
        uint256 positionNotional,
        uint256 positionSize,
        uint256 feeToLiquidator,
        uint256 feeToInsuranceFund,
        address liquidator,
        uint256 badDebt
    );

    modifier checkAccess() {
        if (whitelistMaster != address(0)) {
            require(IWhitelistMaster(whitelistMaster).isWhitelisted(_msgSender()), "CH_NW"); // not whitelisted
        }
        _;
    }

    function initialize(IInsuranceFund _insuranceFund) public initializer {
        _requireNonZeroAddress(address(_insuranceFund));

        __OwnerPausable_init();

        __ReentrancyGuard_init();

        insuranceFund = _insuranceFund;
    }

    //
    // External
    //

    /**
     * @notice make protocol private that works for only whitelisted users
     * @dev only owner can call
     * @param _whitelistMaster the address of whitelist master where the whitelisted addresses are stored
     */
    function makePrivate(address _whitelistMaster) external onlyOwner {
        _requireNonZeroAddress(_whitelistMaster);
        whitelistMaster = _whitelistMaster;
    }

    /**
     * @notice make protocol public that works for all
     * @dev only owner can call
     */
    function makePublic() external onlyOwner {
        whitelistMaster = address(0);
    }

    /**
     * @notice set the toll pool address
     * @dev only owner can call
     */
    function setTollPool(address _tollPool) external onlyOwner {
        _requireNonZeroAddress(_tollPool);
        tollPool = IMultiTokenRewardRecipient(_tollPool);
    }

    /**
     * @notice set backstop liquidity provider
     * @dev only owner can call
     * @param account provider address
     * @param isProvider wether the account is a backstop liquidity provider
     */
    function setBackstopLiquidityProvider(address account, bool isProvider) external onlyOwner {
        _requireNonZeroAddress(account);
        backstopLiquidityProviderMap[account] = isProvider;
        emit BackstopLiquidityProviderChanged(account, isProvider);
    }

    /**
     * @dev only the insurance fund can call this function
     */
    function depositCallback(IERC20 _token, uint256 _amount) external {
        require(_msgSender() == address(insuranceFund), "CH_NIF"); // not insurnce fund
        _token.safeTransfer(address(insuranceFund), _amount);
    }

    /**
     * @notice add margin to increase margin ratio
     * @param _amm IAmm address
     * @param _addedMargin added margin in 18 digits
     */
    function addMargin(IAmm _amm, uint256 _addedMargin) external whenNotPaused nonReentrant checkAccess {
        // check condition
        _requireAmm(_amm, true);
        _requireNonZeroInput(_addedMargin);

        address trader = _msgSender();
        Position memory position = getPosition(_amm, trader);
        // update margin
        position.margin = position.margin + _addedMargin.toInt();

        _setPosition(_amm, trader, position);
        // transfer token from trader
        _deposit(_amm, trader, _addedMargin);
        emit MarginChanged(trader, address(_amm), int256(_addedMargin), 0);
    }

    /**
     * @notice remove margin to decrease margin ratio
     * @param _amm IAmm address
     * @param _removedMargin removed margin in 18 digits
     */
    function removeMargin(IAmm _amm, uint256 _removedMargin) external whenNotPaused nonReentrant checkAccess {
        // check condition
        _requireAmm(_amm, true);
        _requireNonZeroInput(_removedMargin);

        address trader = _msgSender();
        // realize funding payment if there's no bad debt
        Position memory position = getPosition(_amm, trader);

        // update margin and cumulativePremiumFraction
        int256 marginDelta = _removedMargin.toInt() * -1;
        (
            int256 remainMargin,
            uint256 badDebt,
            int256 fundingPayment,
            int256 latestCumulativePremiumFraction
        ) = _calcRemainMarginWithFundingPayment(_amm, position, marginDelta, position.size > 0);
        require(badDebt == 0, "CH_MNE"); // margin is not enough
        position.margin = remainMargin;
        position.lastUpdatedCumulativePremiumFraction = latestCumulativePremiumFraction;

        // check enough margin (same as the way Curie calculates the free collateral)
        // Use a more conservative way to restrict traders to remove their margin
        // We don't allow unrealized PnL to support their margin removal
        require(_calcFreeCollateral(_amm, trader, remainMargin) >= 0, "CH_FCNE"); //free collateral is not enough

        _setPosition(_amm, trader, position);

        // transfer token back to trader
        _withdraw(_amm, trader, _removedMargin);
        emit MarginChanged(trader, address(_amm), marginDelta, fundingPayment);
    }

    /**
     * @notice settle all the positions when amm is shutdown. The settlement price is according to IAmm.settlementPrice
     * @param _amm IAmm address
     */
    function settlePosition(IAmm _amm) external nonReentrant checkAccess {
        // check condition
        _requireAmm(_amm, false);
        address trader = _msgSender();
        Position memory pos = getPosition(_amm, trader);
        _requirePositionSize(pos.size);
        // update position
        _setPosition(
            _amm,
            trader,
            Position({ size: 0, margin: 0, openNotional: 0, lastUpdatedCumulativePremiumFraction: 0, blockNumber: _blockNumber() })
        );
        // calculate settledValue
        // If Settlement Price = 0, everyone takes back her collateral.
        // else Returned Fund = Position Size * (Settlement Price - Open Price) + Collateral
        uint256 settlementPrice = _amm.getSettlementPrice();
        uint256 settledValue;
        if (settlementPrice == 0 && pos.margin > 0) {
            settledValue = pos.margin.abs();
        } else {
            // returnedFund = positionSize * (settlementPrice - openPrice) + positionMargin
            // openPrice = positionOpenNotional / positionSize.abs()
            int256 returnedFund = pos.size.mulD(settlementPrice.toInt() - (pos.openNotional.divD(pos.size.abs())).toInt()) + pos.margin;
            // if `returnedFund` is negative, trader can't get anything back
            if (returnedFund > 0) {
                settledValue = returnedFund.abs();
            }
        }
        // transfer token based on settledValue. no insurance fund support
        if (settledValue > 0) {
            _withdraw(_amm, trader, settledValue);
            // _amm.quoteAsset().safeTransfer(trader, settledValue);
            //_transfer(_amm.quoteAsset(), trader, settledValue);
        }
        // emit event
        emit PositionSettled(address(_amm), trader, settledValue);
    }

    // if increase position
    //   marginToVault = addMargin
    //   marginDiff = realizedFundingPayment + realizedPnl(0)
    //   pos.margin += marginToVault + marginDiff
    //   vault.margin += marginToVault + marginDiff
    //   required(enoughMarginRatio)
    // else if reduce position()
    //   marginToVault = 0
    //   marginDiff = realizedFundingPayment + realizedPnl
    //   pos.margin += marginToVault + marginDiff
    //   if pos.margin < 0, badDebt = abs(pos.margin), set pos.margin = 0
    //   vault.margin += marginToVault + marginDiff
    //   required(enoughMarginRatio)
    // else if close
    //   marginDiff = realizedFundingPayment + realizedPnl
    //   pos.margin += marginDiff
    //   if pos.margin < 0, badDebt = abs(pos.margin)
    //   marginToVault = -pos.margin
    //   set pos.margin = 0
    //   vault.margin += marginToVault + marginDiff
    // else if close and open a larger position in reverse side
    //   close()
    //   positionNotional -= exchangedQuoteAssetAmount
    //   newMargin = positionNotional / leverage
    //   _increasePosition(newMargin, leverage)
    // else if liquidate
    //   close()
    //   pay liquidation fee to liquidator
    //   move the remain margin to insuranceFund

    /**
     * @notice open a position
     * @param _amm amm address
     * @param _side enum Side; BUY for long and SELL for short
     * @param _amount leveraged asset amount to be exact amount in 18 digits. Can Not be 0
     * @param _leverage leverage  in 18 digits. Can Not be 0
     * @param _oppositeAmountBound minimum or maxmum asset amount expected to get to prevent from slippage.
     * @param _isQuote if _assetAmount is quote asset, then true, otherwise false.
     */
    function openPosition(
        IAmm _amm,
        Side _side,
        uint256 _amount,
        uint256 _leverage,
        uint256 _oppositeAmountBound,
        bool _isQuote
    ) external whenNotPaused nonReentrant checkAccess {
        _requireAmm(_amm, true);
        _requireNonZeroInput(_amount);
        _requireNonZeroInput(_leverage);
        _requireMoreMarginRatio(int256(1 ether).divD(_leverage.toInt()), _amm.initMarginRatio(), true);
        _requireNotRestrictionMode(_amm);

        address trader = _msgSender();
        PositionResp memory positionResp;
        {
            // add scope for stack too deep error
            int256 oldPositionSize = getPosition(_amm, trader).size;
            bool isNewPosition = oldPositionSize == 0 ? true : false;

            // increase or decrease position depends on old position's side and size
            if (isNewPosition || (oldPositionSize > 0 ? Side.BUY : Side.SELL) == _side) {
                positionResp = _increasePosition(
                    InternalOpenPositionParams({
                        amm: _amm,
                        side: _side,
                        trader: trader,
                        amount: _amount,
                        leverage: _leverage,
                        isQuote: _isQuote,
                        canOverFluctuationLimit: false
                    })
                );
            } else {
                positionResp = _openReversePosition(
                    InternalOpenPositionParams({
                        amm: _amm,
                        side: _side,
                        trader: trader,
                        amount: _amount,
                        leverage: _leverage,
                        isQuote: _isQuote,
                        canOverFluctuationLimit: false
                    })
                );
            }

            _checkSlippage(
                _side,
                positionResp.exchangedQuoteAssetAmount,
                positionResp.exchangedPositionSize.abs(),
                _oppositeAmountBound,
                _isQuote
            );

            // update the position state
            _setPosition(_amm, trader, positionResp.position);
            // if opening the exact position size as the existing one == closePosition, can skip the margin ratio check
            if (positionResp.position.size != 0) {
                _requireMoreMarginRatio(getMarginRatio(_amm, trader), _amm.maintenanceMarginRatio(), true);
            }

            // to prevent attacker to leverage the bad debt to withdraw extra token from insurance fund
            require(positionResp.badDebt == 0, "CH_BDP"); //bad debt position

            // transfer the actual token between trader and vault
            if (positionResp.marginToVault > 0) {
                _deposit(_amm, trader, positionResp.marginToVault.abs());
            } else if (positionResp.marginToVault < 0) {
                _withdraw(_amm, trader, positionResp.marginToVault.abs());
            }
        }

        // transfer token for fees
        _transferFee(trader, _amm, positionResp.spreadFee, positionResp.tollFee);

        // emit event
        uint256 spotPrice = _amm.getSpotPrice();
        int256 fundingPayment = positionResp.fundingPayment; // pre-fetch for stack too deep error
        emit PositionChanged(
            trader,
            address(_amm),
            positionResp.position.margin,
            positionResp.exchangedQuoteAssetAmount,
            positionResp.exchangedPositionSize,
            positionResp.spreadFee + positionResp.tollFee,
            positionResp.position.size,
            positionResp.realizedPnl,
            positionResp.unrealizedPnlAfter,
            positionResp.badDebt,
            0,
            spotPrice,
            fundingPayment
        );
    }

    /**
     * @notice close all the positions
     * @param _amm IAmm address
     */
    function closePosition(IAmm _amm, uint256 _quoteAssetAmountLimit) external whenNotPaused nonReentrant checkAccess {
        // check conditions
        _requireAmm(_amm, true);
        _requireNotRestrictionMode(_amm);

        // update position
        address trader = _msgSender();

        PositionResp memory positionResp;
        {
            Position memory position = getPosition(_amm, trader);
            // // if it is long position, close a position means short it(which means base dir is ADD_TO_AMM) and vice versa
            // IAmm.Dir dirOfBase = position.size > 0 ? IAmm.Dir.ADD_TO_AMM : IAmm.Dir.REMOVE_FROM_AMM;

            positionResp = _closePosition(_amm, trader, false);
            _checkSlippage(
                position.size > 0 ? Side.SELL : Side.BUY,
                positionResp.exchangedQuoteAssetAmount,
                positionResp.exchangedPositionSize.abs(),
                _quoteAssetAmountLimit,
                false
            );

            // to prevent attacker to leverage the bad debt to withdraw extra token from insurance fund
            require(positionResp.badDebt == 0, "CH_BDP"); //bad debt position

            _setPosition(_amm, trader, positionResp.position);

            // add scope for stack too deep error
            // transfer the actual token from trader and vault
            _withdraw(_amm, trader, positionResp.marginToVault.abs());
        }

        // transfer token for fees
        _transferFee(trader, _amm, positionResp.spreadFee, positionResp.tollFee);

        // prepare event
        uint256 spotPrice = _amm.getSpotPrice();
        int256 fundingPayment = positionResp.fundingPayment;
        emit PositionChanged(
            trader,
            address(_amm),
            positionResp.position.margin,
            positionResp.exchangedQuoteAssetAmount,
            positionResp.exchangedPositionSize,
            positionResp.spreadFee + positionResp.tollFee,
            positionResp.position.size,
            positionResp.realizedPnl,
            positionResp.unrealizedPnlAfter,
            positionResp.badDebt,
            0,
            spotPrice,
            fundingPayment
        );
    }

    function liquidateWithSlippage(
        IAmm _amm,
        address _trader,
        uint256 _quoteAssetAmountLimit
    ) external nonReentrant checkAccess returns (uint256 quoteAssetAmount, bool isPartialClose) {
        Position memory position = getPosition(_amm, _trader);
        (quoteAssetAmount, isPartialClose) = _liquidate(_amm, _trader);

        uint256 quoteAssetAmountLimit = isPartialClose
            ? _quoteAssetAmountLimit.mulD(_amm.partialLiquidationRatio())
            : _quoteAssetAmountLimit;

        _checkSlippage(position.size > 0 ? Side.SELL : Side.BUY, quoteAssetAmount, 0, quoteAssetAmountLimit, false);

        return (quoteAssetAmount, isPartialClose);
    }

    /**
     * @notice liquidate trader's underwater position. Require trader's margin ratio less than maintenance margin ratio
     * @dev liquidator can NOT open any positions in the same block to prevent from price manipulation.
     * @param _amm IAmm address
     * @param _trader trader address
     */
    function liquidate(IAmm _amm, address _trader) external nonReentrant checkAccess {
        _liquidate(_amm, _trader);
    }

    /**
     * @notice if funding rate is positive, traders with long position pay traders with short position and vice versa.
     * @param _amm IAmm address
     */
    function payFunding(IAmm _amm) external checkAccess {
        _requireAmm(_amm, true);
        uint256 budget = insuranceFund.getAvailableBudgetFor(_amm);
        bool repegable;
        int256 repegCost;
        uint256 newQuoteAssetReserve;
        uint256 newBaseAssetReserve;
        int256 kRevenueWithRepeg; // k revenue after having done repeg
        int256 kRevenueWithoutRepeg; // k revenue without repeg

        // ------------------- funding payment ---------------------//
        int256 fundingPayment;
        {
            uint256 totalReserveForFunding = budget; // reserve allocated for the funding payment
            {
                (uint256 quoteAssetReserve, uint256 baseAssetReserve) = _amm.getReserve();
                kRevenueWithoutRepeg = _amm.getMaxKDecreaseRevenue(quoteAssetReserve, baseAssetReserve); // always positive
                totalReserveForFunding = budget + kRevenueWithoutRepeg.abs();

                // repegable is always true when repeg is needed because of max budget
                (repegable, repegCost, newQuoteAssetReserve, newBaseAssetReserve) = _amm.repegCheck(type(uint256).max);
                if (repegable) {
                    kRevenueWithRepeg = _amm.getMaxKDecreaseRevenue(newQuoteAssetReserve, newBaseAssetReserve);
                    if (kRevenueWithRepeg - repegCost > kRevenueWithoutRepeg) {
                        // in this case,
                        // if the funding payment is not enough with budget+kRevenueWithRepeg-cost, then it is also not enough without repeg, hence amm is shut down in all cases
                        // if it is enough, then repeg also will be done later, as a result have no budget error
                        totalReserveForFunding = budget + (kRevenueWithRepeg - repegCost).abs();
                    }
                    // in the other case where "kRevenueWithRepeg-cost <= kRevenueWithoutRepeg"
                    // if the funding payment is not enough with budget+kRevenueWithoutRepeg, then it is also not enough with repeg, hence amm is shut down in all cases
                    // if it is enough, then repeg is optional. if budget+kRevenueWithRepeg-fundingcost >= cost, repeg is done, otherwise repeg is not done
                }
            }

            int256 premiumFractionLong;
            int256 premiumFractionShort;
            // pay funding considering the revenue from k decreasing
            // if fundingPayment <= totalReserveForFunding, funding pay is done, otherwise amm is shut down and fundingPayment = 0
            (premiumFractionLong, premiumFractionShort, fundingPayment) = _amm.settleFunding(totalReserveForFunding);
            ammMap[address(_amm)].latestCumulativePremiumFractionLong = premiumFractionLong + getLatestCumulativePremiumFractionLong(_amm);
            ammMap[address(_amm)].latestCumulativePremiumFractionShort =
                premiumFractionShort +
                getLatestCumulativePremiumFractionShort(_amm);
        }

        // positive funding payment means profit, so reverse it
        int256 adjustmentCost = -1 * fundingPayment;
        // --------------------------------------------------------//

        // -------------------      repeg     ---------------------//
        // if amm was not shut down by funding pay and repeg is needed,
        // and the repeg cost is smaller than the "budget+kRevenueWithRepeg+fundingPayment", then repeg is done
        if (_amm.open() && repegable && (budget.toInt() + kRevenueWithRepeg + fundingPayment >= repegCost)) {
            _amm.adjust(newQuoteAssetReserve, newBaseAssetReserve);
            adjustmentCost += repegCost;
            emit Repeg(address(_amm), newQuoteAssetReserve, newBaseAssetReserve, repegCost);
        } else {
            repegable = false;
        }
        // --------------------------------------------------------//

        // -------------------    update K    ---------------------//
        {
            int256 budgetForUpdateK = netRevenuesSinceLastFunding[_amm] + fundingPayment - repegCost; // consider repegCost regardless whether it happens or not
            if (budgetForUpdateK > 0) {
                // if the overall sum is a REVENUE to the system, give back 25% of the REVENUE in k increase
                budgetForUpdateK = budgetForUpdateK / 4;
            } else {
                // if the overall sum is a COST to the system, take back half of the COST in k decrease
                budgetForUpdateK = budgetForUpdateK / 2;
            }
            bool isAdjustable;
            int256 kAdjustmentCost;
            (isAdjustable, kAdjustmentCost, newQuoteAssetReserve, newBaseAssetReserve) = _amm.getFormulaicUpdateKResult(budgetForUpdateK);
            // adjustmentCost + kAdjustmentCost should be smaller than insurance fund budget
            // otherwise do max decrease K
            if (adjustmentCost + kAdjustmentCost > budget.toInt()) {
                (isAdjustable, kAdjustmentCost, newQuoteAssetReserve, newBaseAssetReserve) = _amm.getFormulaicUpdateKResult(
                    repegable ? -kRevenueWithRepeg : -kRevenueWithoutRepeg
                );
            }
            if (isAdjustable) {
                _amm.adjust(newQuoteAssetReserve, newBaseAssetReserve);
                emit UpdateK(address(_amm), newQuoteAssetReserve, newBaseAssetReserve, kAdjustmentCost);
            }

            // apply all cost/revenue
            _applyAdjustmentCost(_amm, adjustmentCost + kAdjustmentCost);
        }
        // --------------------------------------------------------//

        // init netRevenuesSinceLastFunding for the next funding period's revenue
        netRevenuesSinceLastFunding[_amm] = 0;
        _enterRestrictionMode(_amm);
    }

    //
    // VIEW FUNCTIONS
    //

    /**
     * @notice get margin ratio, marginRatio = (margin + funding payment + unrealized Pnl) / positionNotional
     * use spot price to calculate unrealized Pnl and positionNotional when the price gap is not over the spread limit
     * use oracle price to calculate them when the price gap is over the spread limit
     * @param _amm IAmm address
     * @param _trader trader address
     * @return margin ratio in 18 digits
     */
    function getMarginRatio(IAmm _amm, address _trader) public view returns (int256) {
        (bool isOverSpread, , ) = _amm.isOverSpread(LIQ_SWITCH_RATIO);
        if (isOverSpread) {
            return _getMarginRatioByCalcOption(_amm, _trader, PnlCalcOption.ORACLE);
        } else {
            return _getMarginRatioByCalcOption(_amm, _trader, PnlCalcOption.SPOT_PRICE);
        }
    }

    /**
     * @notice get personal position information
     * @param _amm IAmm address
     * @param _trader trader address
     * @return struct Position
     */
    function getPosition(IAmm _amm, address _trader) public view returns (Position memory) {
        return ammMap[address(_amm)].positionMap[_trader];
    }

    /**
     * @notice get position notional and unrealized Pnl without fee expense and funding payment
     * @param _amm IAmm address
     * @param _trader trader address
     * @param _pnlCalcOption enum PnlCalcOption, SPOT_PRICE for spot price and TWAP for twap price
     * @return positionNotional position notional
     * @return unrealizedPnl unrealized Pnl
     */
    function getPositionNotionalAndUnrealizedPnl(
        IAmm _amm,
        address _trader,
        PnlCalcOption _pnlCalcOption
    ) public view returns (uint256 positionNotional, int256 unrealizedPnl) {
        Position memory position = getPosition(_amm, _trader);
        uint256 positionSizeAbs = position.size.abs();
        if (positionSizeAbs != 0) {
            bool isShortPosition = position.size < 0;
            IAmm.Dir dir = isShortPosition ? IAmm.Dir.REMOVE_FROM_AMM : IAmm.Dir.ADD_TO_AMM;
            if (_pnlCalcOption == PnlCalcOption.TWAP) {
                positionNotional = _amm.getBaseTwap(dir, positionSizeAbs);
            } else if (_pnlCalcOption == PnlCalcOption.SPOT_PRICE) {
                positionNotional = _amm.getBasePrice(dir, positionSizeAbs);
            } else {
                uint256 oraclePrice = _amm.getUnderlyingPrice();
                positionNotional = positionSizeAbs.mulD(oraclePrice);
            }
            // unrealizedPnlForLongPosition = positionNotional - openNotional
            // unrealizedPnlForShortPosition = positionNotionalWhenBorrowed - positionNotionalWhenReturned =
            // openNotional - positionNotional = unrealizedPnlForLongPosition * -1
            unrealizedPnl = isShortPosition
                ? position.openNotional.toInt() - positionNotional.toInt()
                : positionNotional.toInt() - position.openNotional.toInt();
        }
    }

    /**
     * @notice get latest cumulative premium fraction for long.
     * @param _amm IAmm address
     * @return latest cumulative premium fraction for long in 18 digits
     */
    function getLatestCumulativePremiumFractionLong(IAmm _amm) public view returns (int256 latest) {
        latest = ammMap[address(_amm)].latestCumulativePremiumFractionLong;
    }

    /**
     * @notice get latest cumulative premium fraction for short.
     * @param _amm IAmm address
     * @return latest cumulative premium fraction for short in 18 digits
     */
    function getLatestCumulativePremiumFractionShort(IAmm _amm) public view returns (int256 latest) {
        latest = ammMap[address(_amm)].latestCumulativePremiumFractionShort;
    }

    function getVaultFor(IAmm _amm) external view override returns (uint256 vault) {
        vault = vaults[_amm];
    }

    function _enterRestrictionMode(IAmm _amm) internal {
        uint256 blockNumber = _blockNumber();
        ammMap[address(_amm)].lastRestrictionBlock = blockNumber;
        emit RestrictionModeEntered(address(_amm), blockNumber);
    }

    function _setPosition(
        IAmm _amm,
        address _trader,
        Position memory _position
    ) internal {
        Position storage positionStorage = ammMap[address(_amm)].positionMap[_trader];
        positionStorage.size = _position.size;
        positionStorage.margin = _position.margin;
        positionStorage.openNotional = _position.openNotional;
        positionStorage.lastUpdatedCumulativePremiumFraction = _position.lastUpdatedCumulativePremiumFraction;
        positionStorage.blockNumber = _position.blockNumber;
    }

    function _liquidate(IAmm _amm, address _trader) internal returns (uint256 quoteAssetAmount, bool isPartialClose) {
        _requireAmm(_amm, true);
        _requireMoreMarginRatio(getMarginRatio(_amm, _trader), _amm.maintenanceMarginRatio(), false);

        PositionResp memory positionResp;
        uint256 liquidationPenalty;
        {
            uint256 liquidationBadDebt;
            uint256 feeToLiquidator;
            uint256 feeToInsuranceFund;

            int256 marginRatioBasedOnSpot = _getMarginRatioByCalcOption(_amm, _trader, PnlCalcOption.SPOT_PRICE);
            uint256 _partialLiquidationRatio = _amm.partialLiquidationRatio();
            uint256 _liquidationFeeRatio = _amm.liquidationFeeRatio();
            if (
                // check margin(based on spot price) is enough to pay the liquidation fee
                // after partially close, otherwise we fully close the position.
                // that also means we can ensure no bad debt happen when partially liquidate
                marginRatioBasedOnSpot > int256(_liquidationFeeRatio) && _partialLiquidationRatio < 1 ether && _partialLiquidationRatio != 0
            ) {
                Position memory position = getPosition(_amm, _trader);
                positionResp = _openReversePosition(
                    InternalOpenPositionParams({
                        amm: _amm,
                        side: position.size > 0 ? Side.SELL : Side.BUY,
                        trader: _trader,
                        amount: position.size.mulD(_partialLiquidationRatio.toInt()).abs(),
                        leverage: 1 ether,
                        isQuote: false,
                        canOverFluctuationLimit: true
                    })
                );

                // half of the liquidationFee goes to liquidator & another half goes to insurance fund
                liquidationPenalty = positionResp.exchangedQuoteAssetAmount.mulD(_liquidationFeeRatio);
                feeToLiquidator = liquidationPenalty / 2;
                feeToInsuranceFund = liquidationPenalty - feeToLiquidator;

                positionResp.position.margin = positionResp.position.margin - liquidationPenalty.toInt();
                _setPosition(_amm, _trader, positionResp.position);

                isPartialClose = true;
            } else {
                // liquidationPenalty = getPosition(_amm, _trader).margin.abs();
                positionResp = _closePosition(_amm, _trader, true);
                uint256 remainMargin = positionResp.marginToVault < 0 ? positionResp.marginToVault.abs() : 0;
                feeToLiquidator = positionResp.exchangedQuoteAssetAmount.mulD(_liquidationFeeRatio) / 2;

                // if the remainMargin is not enough for liquidationFee, count it as bad debt
                // else, then the rest will be transferred to insuranceFund
                liquidationBadDebt = positionResp.badDebt;
                if (feeToLiquidator > remainMargin) {
                    liquidationPenalty = feeToLiquidator;
                    liquidationBadDebt = liquidationBadDebt + feeToLiquidator - remainMargin;
                    remainMargin = 0;
                } else {
                    liquidationPenalty = remainMargin;
                    remainMargin = remainMargin - feeToLiquidator;
                }
                // transfer the actual token between trader and vault
                if (liquidationBadDebt > 0) {
                    require(backstopLiquidityProviderMap[_msgSender()], "CH_NBLP"); //not backstop LP
                    _realizeBadDebt(_amm, liquidationBadDebt);
                    // include liquidation bad debt into the k-adjustment calculation
                    netRevenuesSinceLastFunding[_amm] -= int256(liquidationBadDebt);
                }
                feeToInsuranceFund = remainMargin;
                _setPosition(_amm, _trader, positionResp.position);
            }

            _withdraw(_amm, _msgSender(), feeToLiquidator);

            if (feeToInsuranceFund > 0) {
                _transferToInsuranceFund(_amm, feeToInsuranceFund);
                // include liquidation fee to the insurance fund into the k-adjustment calculation
                netRevenuesSinceLastFunding[_amm] += int256(feeToInsuranceFund);
            }

            _enterRestrictionMode(_amm);

            emit PositionLiquidated(
                _trader,
                address(_amm),
                positionResp.exchangedQuoteAssetAmount,
                positionResp.exchangedPositionSize.toUint(),
                feeToLiquidator,
                feeToInsuranceFund,
                _msgSender(),
                liquidationBadDebt
            );
        }

        // emit event
        uint256 spotPrice = _amm.getSpotPrice();
        emit PositionChanged(
            _trader,
            address(_amm),
            positionResp.position.margin,
            positionResp.exchangedQuoteAssetAmount,
            positionResp.exchangedPositionSize,
            0,
            positionResp.position.size,
            positionResp.realizedPnl,
            positionResp.unrealizedPnlAfter,
            positionResp.badDebt,
            liquidationPenalty,
            spotPrice,
            positionResp.fundingPayment
        );

        return (positionResp.exchangedQuoteAssetAmount, isPartialClose);
    }

    // only called from openPosition and _closeAndOpenReversePosition. caller need to ensure there's enough marginRatio
    function _increasePosition(InternalOpenPositionParams memory params) internal returns (PositionResp memory positionResp) {
        Position memory oldPosition = getPosition(params.amm, params.trader);
        (, int256 unrealizedPnl) = getPositionNotionalAndUnrealizedPnl(params.amm, params.trader, PnlCalcOption.SPOT_PRICE);
        (positionResp.exchangedQuoteAssetAmount, positionResp.exchangedPositionSize, positionResp.spreadFee, positionResp.tollFee) = params
            .amm
            .swapInput(
                params.isQuote == (params.side == Side.BUY) ? IAmm.Dir.ADD_TO_AMM : IAmm.Dir.REMOVE_FROM_AMM,
                params.amount,
                params.isQuote,
                params.canOverFluctuationLimit
            );

        int256 newSize = oldPosition.size + positionResp.exchangedPositionSize;

        int256 increaseMarginRequirement = positionResp.exchangedQuoteAssetAmount.divD(params.leverage).toInt();
        (
            int256 remainMargin,
            uint256 badDebt,
            int256 fundingPayment,
            int256 latestCumulativePremiumFraction
        ) = _calcRemainMarginWithFundingPayment(params.amm, oldPosition, increaseMarginRequirement, params.side == Side.BUY);

        // update positionResp
        positionResp.badDebt = badDebt;
        positionResp.unrealizedPnlAfter = unrealizedPnl;
        positionResp.marginToVault = increaseMarginRequirement;
        positionResp.fundingPayment = fundingPayment;
        positionResp.position = Position(
            newSize, //Number of base asset (e.g. BAYC)
            remainMargin,
            oldPosition.openNotional + positionResp.exchangedQuoteAssetAmount, //In Quote Asset (e.g. USDC)
            latestCumulativePremiumFraction,
            _blockNumber()
        );
    }

    function _openReversePosition(InternalOpenPositionParams memory params) internal returns (PositionResp memory) {
        (uint256 oldPositionNotional, int256 unrealizedPnl) = getPositionNotionalAndUnrealizedPnl(
            params.amm,
            params.trader,
            PnlCalcOption.SPOT_PRICE
        );
        Position memory oldPosition = getPosition(params.amm, params.trader);
        PositionResp memory positionResp;

        // reduce position if old position is larger
        if (params.isQuote ? oldPositionNotional > params.amount : oldPosition.size.abs() > params.amount) {
            (
                positionResp.exchangedQuoteAssetAmount,
                positionResp.exchangedPositionSize,
                positionResp.spreadFee,
                positionResp.tollFee
            ) = params.amm.swapOutput(
                params.isQuote == (params.side == Side.BUY) ? IAmm.Dir.ADD_TO_AMM : IAmm.Dir.REMOVE_FROM_AMM,
                params.amount,
                params.isQuote,
                params.canOverFluctuationLimit
            );
            if (oldPosition.size != 0) {
                positionResp.realizedPnl = unrealizedPnl.mulD(positionResp.exchangedPositionSize.abs().toInt()).divD(
                    oldPosition.size.abs().toInt()
                );
            }
            int256 remainMargin;
            int256 latestCumulativePremiumFraction;
            (
                remainMargin,
                positionResp.badDebt,
                positionResp.fundingPayment,
                latestCumulativePremiumFraction
            ) = _calcRemainMarginWithFundingPayment(params.amm, oldPosition, positionResp.realizedPnl, oldPosition.size > 0);

            // positionResp.unrealizedPnlAfter = unrealizedPnl - realizedPnl
            positionResp.unrealizedPnlAfter = unrealizedPnl - positionResp.realizedPnl;

            // calculate openNotional (it's different depends on long or short side)
            // long: unrealizedPnl = positionNotional - openNotional => openNotional = positionNotional - unrealizedPnl
            // short: unrealizedPnl = openNotional - positionNotional => openNotional = positionNotional + unrealizedPnl
            // positionNotional = oldPositionNotional - exchangedQuoteAssetAmount
            int256 remainOpenNotional = oldPosition.size > 0
                ? oldPositionNotional.toInt() - positionResp.exchangedQuoteAssetAmount.toInt() - positionResp.unrealizedPnlAfter
                : positionResp.unrealizedPnlAfter + oldPositionNotional.toInt() - positionResp.exchangedQuoteAssetAmount.toInt();
            require(remainOpenNotional > 0, "CH_ONNP"); // open notional value is not positive

            positionResp.position = Position(
                oldPosition.size + positionResp.exchangedPositionSize,
                remainMargin,
                remainOpenNotional.abs(),
                latestCumulativePremiumFraction,
                _blockNumber()
            );
            return positionResp;
        }

        return _closeAndOpenReversePosition(params);
    }

    function _closeAndOpenReversePosition(InternalOpenPositionParams memory params) internal returns (PositionResp memory positionResp) {
        // new position size is larger than or equal to the old position size
        // so either close or close then open a larger position
        PositionResp memory closePositionResp = _closePosition(params.amm, params.trader, params.canOverFluctuationLimit);

        // the old position is underwater. trader should close a position first
        require(closePositionResp.badDebt == 0, "CH_BDP"); // bad debt position

        // update open notional after closing position
        uint256 amount = params.isQuote
            ? params.amount - closePositionResp.exchangedQuoteAssetAmount
            : params.amount - closePositionResp.exchangedPositionSize.abs();

        // if remain asset amount is too small (eg. 100 wei) then the required margin might be 0
        // then the clearingHouse will stop opening position
        if (amount <= 100 wei) {
            positionResp = closePositionResp;
        } else {
            _setPosition(params.amm, params.trader, closePositionResp.position);
            params.amount = amount;
            PositionResp memory increasePositionResp = _increasePosition(params);
            positionResp = PositionResp({
                position: increasePositionResp.position,
                exchangedQuoteAssetAmount: closePositionResp.exchangedQuoteAssetAmount + increasePositionResp.exchangedQuoteAssetAmount,
                badDebt: closePositionResp.badDebt + increasePositionResp.badDebt,
                fundingPayment: closePositionResp.fundingPayment + increasePositionResp.fundingPayment,
                exchangedPositionSize: closePositionResp.exchangedPositionSize + increasePositionResp.exchangedPositionSize,
                realizedPnl: closePositionResp.realizedPnl + increasePositionResp.realizedPnl,
                unrealizedPnlAfter: 0,
                marginToVault: closePositionResp.marginToVault + increasePositionResp.marginToVault,
                spreadFee: closePositionResp.spreadFee + increasePositionResp.spreadFee,
                tollFee: closePositionResp.tollFee + increasePositionResp.tollFee
            });
        }
        return positionResp;
    }

    function _closePosition(
        IAmm _amm,
        address _trader,
        bool _canOverFluctuationLimit
    ) internal returns (PositionResp memory positionResp) {
        // check conditions
        Position memory oldPosition = getPosition(_amm, _trader);
        _requirePositionSize(oldPosition.size);

        (, int256 unrealizedPnl) = getPositionNotionalAndUnrealizedPnl(_amm, _trader, PnlCalcOption.SPOT_PRICE);
        (int256 remainMargin, uint256 badDebt, int256 fundingPayment, ) = _calcRemainMarginWithFundingPayment(
            _amm,
            oldPosition,
            unrealizedPnl,
            oldPosition.size > 0
        );

        positionResp.realizedPnl = unrealizedPnl;
        positionResp.badDebt = badDebt;
        positionResp.fundingPayment = fundingPayment;
        positionResp.marginToVault = remainMargin * -1;
        positionResp.position = Position({
            size: 0,
            margin: 0,
            openNotional: 0,
            lastUpdatedCumulativePremiumFraction: 0,
            blockNumber: _blockNumber()
        });

        (positionResp.exchangedQuoteAssetAmount, positionResp.exchangedPositionSize, positionResp.spreadFee, positionResp.tollFee) = _amm
            .swapOutput(
                oldPosition.size > 0 ? IAmm.Dir.ADD_TO_AMM : IAmm.Dir.REMOVE_FROM_AMM,
                oldPosition.size.abs(),
                false,
                _canOverFluctuationLimit
            );
    }

    function _checkSlippage(
        Side _side,
        uint256 _quote,
        uint256 _base,
        uint256 _oppositeAmountBound,
        bool _isQuote
    ) internal pure {
        // skip when _oppositeAmountBound is zero
        if (_oppositeAmountBound == 0) {
            return;
        }
        // long + isQuote, want more output base as possible, so we set a lower bound of output base
        // short + isQuote, want less input base as possible, so we set a upper bound of input base
        // long + !isQuote, want less input quote as possible, so we set a upper bound of input quote
        // short + !isQuote, want more output quote as possible, so we set a lower bound of output quote
        if (_isQuote) {
            if (_side == Side.BUY) {
                // too little received when long
                require(_base >= _oppositeAmountBound, "CH_TLRL");
            } else {
                // too much requested when short
                require(_base <= _oppositeAmountBound, "CH_TMRS");
            }
        } else {
            if (_side == Side.BUY) {
                // too much requested when long
                require(_quote <= _oppositeAmountBound, "CH_TMRL");
            } else {
                // too little received when short
                require(_quote >= _oppositeAmountBound, "CH_TLRS");
            }
        }
    }

    function _transferFee(
        address _from,
        IAmm _amm,
        uint256 _spreadFee,
        uint256 _tollFee
    ) internal {
        IERC20 quoteAsset = _amm.quoteAsset();

        // transfer spread to market in order to use it to make market better
        if (_spreadFee > 0) {
            quoteAsset.safeTransferFrom(_from, address(this), _spreadFee);
            insuranceFund.deposit(_amm, _spreadFee);
            // consider fees in k-adjustment
            netRevenuesSinceLastFunding[_amm] += _spreadFee.toInt();
        }

        // transfer toll to tollPool
        if (_tollFee > 0) {
            _requireNonZeroAddress(address(tollPool));
            quoteAsset.safeTransferFrom(_from, address(tollPool), _tollFee);
        }
    }

    function _deposit(
        IAmm _amm,
        address _sender,
        uint256 _amount
    ) internal {
        vaults[_amm] += _amount;
        IERC20 quoteToken = _amm.quoteAsset();
        quoteToken.safeTransferFrom(_sender, address(this), _amount);
    }

    function _withdraw(
        IAmm _amm,
        address _receiver,
        uint256 _amount
    ) internal {
        // if withdraw amount is larger than the balance of given Amm's vault
        // means this trader's profit comes from other under collateral position's future loss
        // and the balance of given Amm's vault is not enough
        // need money from IInsuranceFund to pay first, and record this prepaidBadDebt
        // in this case, insurance fund loss must be zero
        uint256 vault = vaults[_amm];
        IERC20 quoteToken = _amm.quoteAsset();
        if (vault < _amount) {
            uint256 balanceShortage = _amount - vault;
            prepaidBadDebts[address(_amm)] += balanceShortage;
            _withdrawFromInsuranceFund(_amm, balanceShortage);
        }
        vaults[_amm] -= _amount;
        quoteToken.safeTransfer(_receiver, _amount);
    }

    function _realizeBadDebt(IAmm _amm, uint256 _badDebt) internal {
        uint256 badDebtBalance = prepaidBadDebts[address(_amm)];
        if (badDebtBalance >= _badDebt) {
            // no need to move extra tokens because vault already prepay bad debt, only need to update the numbers
            prepaidBadDebts[address(_amm)] = badDebtBalance - _badDebt;
        } else {
            // in order to realize all the bad debt vault need extra tokens from insuranceFund
            _withdrawFromInsuranceFund(_amm, _badDebt - badDebtBalance);
            prepaidBadDebts[address(_amm)] = 0;
        }
    }

    // withdraw fund from insurance fund to vault
    function _withdrawFromInsuranceFund(IAmm _amm, uint256 _amount) internal {
        vaults[_amm] += _amount;
        insuranceFund.withdraw(_amm, _amount);
    }

    // transfer fund from vault to insurance fund
    function _transferToInsuranceFund(IAmm _amm, uint256 _amount) internal {
        uint256 vault = vaults[_amm];
        if (vault < _amount) {
            _amount = vault;
        }
        vaults[_amm] = vault - _amount;
        insuranceFund.deposit(_amm, _amount);
    }

    /**
     * @notice apply cost for funding payment, repeg and k-adjustment
     * @dev negative cost is revenue, otherwise is expense of insurance fund
     */
    function _applyAdjustmentCost(IAmm _amm, int256 _cost) private {
        if (_cost > 0) {
            _withdrawFromInsuranceFund(_amm, _cost.abs());
        } else if (_cost < 0) {
            _transferToInsuranceFund(_amm, _cost.abs());
        }
    }

    //
    // INTERNAL VIEW FUNCTIONS
    //

    function _getMarginRatioByCalcOption(
        IAmm _amm,
        address _trader,
        PnlCalcOption _pnlCalcOption
    ) internal view returns (int256) {
        Position memory position = getPosition(_amm, _trader);
        _requirePositionSize(position.size);
        (uint256 positionNotional, int256 unrealizedPnl) = getPositionNotionalAndUnrealizedPnl(_amm, _trader, _pnlCalcOption);
        (int256 remainMargin, , , ) = _calcRemainMarginWithFundingPayment(_amm, position, unrealizedPnl, position.size > 0);
        return remainMargin.divD(positionNotional.toInt());
    }

    function _calcRemainMarginWithFundingPayment(
        IAmm _amm,
        Position memory _oldPosition,
        int256 _marginDelta,
        bool isLong
    )
        internal
        view
        returns (
            int256 remainMargin,
            uint256 badDebt,
            int256 fundingPayment,
            int256 latestCumulativePremiumFraction
        )
    {
        // calculate funding payment
        latestCumulativePremiumFraction = isLong
            ? getLatestCumulativePremiumFractionLong(_amm)
            : getLatestCumulativePremiumFractionShort(_amm);
        if (_oldPosition.size != 0) {
            fundingPayment = (latestCumulativePremiumFraction - _oldPosition.lastUpdatedCumulativePremiumFraction).mulD(_oldPosition.size);
        }

        // calculate remain margin
        remainMargin = _marginDelta - fundingPayment + _oldPosition.margin;

        // if remain margin is negative, consider it as bad debt
        if (remainMargin < 0) {
            badDebt = remainMargin.abs();
        }
    }

    /// @param _marginWithFundingPayment margin + funding payment - bad debt
    function _calcFreeCollateral(
        IAmm _amm,
        address _trader,
        int256 _marginWithFundingPayment
    ) internal view returns (int256) {
        Position memory pos = getPosition(_amm, _trader);
        (int256 unrealizedPnl, uint256 positionNotional) = _getPreferencePositionNotionalAndUnrealizedPnl(
            _amm,
            _trader,
            PnlPreferenceOption.MIN_PNL
        );

        // min(margin + funding, margin + funding + unrealized PnL) - position value * initMarginRatio
        int256 accountValue = unrealizedPnl + _marginWithFundingPayment;
        int256 minCollateral = unrealizedPnl > 0 ? _marginWithFundingPayment : accountValue;

        // margin requirement
        // if holding a long position, using open notional (mapping to quote debt in Curie)
        // if holding a short position, using position notional (mapping to base debt in Curie)
        int256 marginRequirement = pos.size > 0
            ? pos.openNotional.toInt().mulD(_amm.initMarginRatio().toInt())
            : positionNotional.toInt().mulD(_amm.initMarginRatio().toInt());

        return minCollateral - marginRequirement;
    }

    function _getPreferencePositionNotionalAndUnrealizedPnl(
        IAmm _amm,
        address _trader,
        PnlPreferenceOption _pnlPreference
    ) internal view returns (int256 unrealizedPnl, uint256 positionNotional) {
        (uint256 spotPositionNotional, int256 spotPricePnl) = (
            getPositionNotionalAndUnrealizedPnl(_amm, _trader, PnlCalcOption.SPOT_PRICE)
        );

        (uint256 twapPositionNotional, int256 twapPricePnl) = (getPositionNotionalAndUnrealizedPnl(_amm, _trader, PnlCalcOption.TWAP));

        // if MAX_PNL
        //    spotPnL >  twapPnL return (spotPnL, spotPositionNotional)
        //    spotPnL <= twapPnL return (twapPnL, twapPositionNotional)
        // if MIN_PNL
        //    spotPnL >  twapPnL return (twapPnL, twapPositionNotional)
        //    spotPnL <= twapPnL return (spotPnL, spotPositionNotional)
        (unrealizedPnl, positionNotional) = (_pnlPreference == PnlPreferenceOption.MAX_PNL) == (spotPricePnl > twapPricePnl)
            ? (spotPricePnl, spotPositionNotional)
            : (twapPricePnl, twapPositionNotional);
    }

    //
    // REQUIRE FUNCTIONS
    //
    function _requireAmm(IAmm _amm, bool _open) private view {
        require(insuranceFund.isExistedAmm(_amm), "CH_ANF"); //vAMM not found
        require(_open == _amm.open(), _open ? "CH_AC" : "CH_AO"); //vAmm is closed, vAmm is opened
    }

    function _requireNonZeroInput(uint256 _input) private pure {
        require(_input != 0, "CH_ZI"); //zero input
    }

    function _requirePositionSize(int256 _size) private pure {
        require(_size != 0, "CH_ZP"); //zero position size
    }

    function _requireNotRestrictionMode(IAmm _amm) private view {
        uint256 currentBlock = _blockNumber();
        if (currentBlock == ammMap[address(_amm)].lastRestrictionBlock) {
            require(getPosition(_amm, _msgSender()).blockNumber != currentBlock, "CH_RM"); //restriction mode, only one action allowed
        }
    }

    function _requireMoreMarginRatio(
        int256 _marginRatio,
        uint256 _baseMarginRatio,
        bool _largerThanOrEqualTo
    ) private pure {
        int256 remainingMarginRatio = _marginRatio - _baseMarginRatio.toInt();
        require(_largerThanOrEqualTo ? remainingMarginRatio >= 0 : remainingMarginRatio < 0, "CH_MRNC"); //Margin ratio not meet criteria
    }

    function _requireRatio(uint256 _ratio) private pure {
        require(_ratio <= 1 ether, "CH_IR"); //invalid ratio
    }

    function _requireNonZeroAddress(address _input) private pure {
        require(_input != address(0), "CH_ZA");
    }
}

