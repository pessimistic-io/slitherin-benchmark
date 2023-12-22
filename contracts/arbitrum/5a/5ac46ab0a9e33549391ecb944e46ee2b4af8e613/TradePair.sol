// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.17;

import "./IERC20Metadata.sol";
import "./SafeERC20.sol";
import "./Initializable.sol";
import "./IFeeManager.sol";
import "./ILiquidityPoolAdapter.sol";
import "./IPriceFeedAdapter.sol";
import "./ITradeManager.sol";
import "./ITradePair.sol";
import "./IUserManager.sol";
import "./ArbitrumBlockchainInfo.sol";
import "./Constants.sol";
import "./UnlimitedOwnable.sol";
import "./FeeBuffer.sol";
import "./FeeIntegral.sol";
import "./PositionMaths.sol";
import "./PositionStats.sol";

contract TradePair is ITradePair, ArbitrumBlockchainInfo, UnlimitedOwnable, Initializable {
    using SafeERC20 for IERC20;
    using FeeIntegralLib for FeeIntegral;
    using FeeBufferLib for FeeBuffer;
    using PositionMaths for Position;
    using PositionStatsLib for PositionStats;

    /* ========== CONSTANTS ========== */

    uint256 private constant SURPLUS_MULTIPLIER = 1_000_000; // 1e6
    uint256 private constant BPS_MULTIPLIER = 100_00; // 1e4

    uint128 private constant MIN_LEVERAGE = 11 * uint128(LEVERAGE_MULTIPLIER) / 10;
    uint128 private constant MAX_LEVERAGE = 100 * uint128(LEVERAGE_MULTIPLIER);

    uint256 private constant USD_TRIM = 10 ** 8;

    enum PositionAlteration {
        partialClose,
        partiallyCloseToLeverage,
        extend,
        extendToLeverage,
        removeMargin,
        addMargin
    }

    /* ========== SYSTEM SMART CONTRACTS ========== */

    /// @notice Trade manager that manages trades.
    ITradeManager public immutable tradeManager;

    /// @notice manages fees per user
    IUserManager public immutable userManager;

    /// @notice Fee Manager that collects and distributes fees
    IFeeManager public immutable feeManager;

    // =============================================================
    //                            STORAGE
    // =============================================================

    /// @notice The price feed to calculate asset to collateral amounts
    IPriceFeedAdapter public priceFeedAdapter;

    /// @notice The liquidity pool adapter that the funds will get borrowed from
    ILiquidityPoolAdapter public liquidityPoolAdapter;

    /// @notice The token that is used as a collateral
    IERC20 public collateral;

    /* ========== PARAMETERS ========== */

    /// @notice The name of this trade pair
    string public name;

    /// @notice Multiplier from collateral to price
    uint256 private _collateralToPriceMultiplier;

    /* ============ INTERNAL SETTINGS ========== */

    /// @notice Minimum Leverage
    uint128 public minLeverage;

    /// @notice Maximum Leverage
    uint128 public maxLeverage;

    /// @notice Minimum margin
    uint256 public minMargin;

    /// @notice Maximum Volume a position can have
    uint256 public volumeLimit;

    /// @notice Total volume limit for each side
    uint256 public totalVolumeLimit;

    /// @notice reward for liquidator
    uint256 public liquidatorReward;

    /* ========== STATE VARIABLES ========== */

    /// @notice The positions of this tradepair
    mapping(uint256 => Position) positions;

    /// @notice Maps position id to the white label address that opened a position
    /// @dev White label recieves part of the open and close position fees collected
    mapping(uint256 => address) public positionIdToWhiteLabel;

    /// @notice increasing counter for the next position id
    uint256 public nextId;

    /// @notice Keeps track of total amounts of positions
    PositionStats public positionStats;

    /// @notice Calculates the fee integrals
    FeeIntegral public feeIntegral;

    /// @notice Keeps track of the fee buffer
    FeeBuffer public feeBuffer;

    /// @notice Amount of overcollected fees
    int256 public overcollectedFees;

    // Storage gap
    uint256[50] __gap;

    /* ========== CONSTRUCTOR ========== */

    /**
     * @notice Constructs the TradePair contract
     * @param unlimitedOwner_ The Unlimited Owner constract
     * @param tradeManager_ The TradeManager contract
     * @param userManager_ The UserManager contract
     * @param feeManager_ The FeeManager contract
     */
    constructor(
        IUnlimitedOwner unlimitedOwner_,
        ITradeManager tradeManager_,
        IUserManager userManager_,
        IFeeManager feeManager_
    ) UnlimitedOwnable(unlimitedOwner_) {
        tradeManager = tradeManager_;
        userManager = userManager_;
        feeManager = feeManager_;
    }

    /**
     * @notice Initializes state variables
     * @param name_ The name of this trade pair
     * @param collateral_ the collateral ERC20 contract
     * @param priceFeedAdapter_ The price feed adapter
     * @param liquidityPoolAdapter_ The liquidity pool adapter
     */
    function initialize(
        string calldata name_,
        IERC20Metadata collateral_,
        IPriceFeedAdapter priceFeedAdapter_,
        ILiquidityPoolAdapter liquidityPoolAdapter_
    ) external onlyOwner initializer {
        name = name_;
        collateral = collateral_;
        liquidityPoolAdapter = liquidityPoolAdapter_;

        setPriceFeedAdapter(priceFeedAdapter_);

        minLeverage = MIN_LEVERAGE;
        maxLeverage = MAX_LEVERAGE;
    }

    /* ========== CORE FUNCTIONS - POSITIONS ========== */

    /**
     * @notice opens a position
     * @param maker_ owner of the position
     * @param margin_ the amount of collateral used as a margin
     * @param leverage_ the target leverage, should respect LEVERAGE_MULTIPLIER
     * @param isShort_ bool if the position is a short position
     */
    function openPosition(address maker_, uint256 margin_, uint256 leverage_, bool isShort_, address whitelabelAddress)
        external
        verifyLeverage(leverage_)
        onlyTradeManager
        syncFeesBefore
        checkTotalVolumeLimit
        returns (uint256)
    {
        if (whitelabelAddress != address(0)) {
            positionIdToWhiteLabel[nextId] = whitelabelAddress;
        }

        return _openPosition(maker_, margin_, leverage_, isShort_);
    }

    /**
     * @dev Should have received margin from TradeManager
     */
    function _openPosition(address maker_, uint256 margin_, uint256 leverage_, bool isShort_)
        private
        returns (uint256)
    {
        require(margin_ >= minMargin, "TradePair::_openPosition: margin must be above or equal min margin");

        uint256 id = nextId;
        nextId++;

        margin_ = _deductAndTransferOpenFee(maker_, margin_, leverage_, id);

        uint256 volume = (margin_ * leverage_) / LEVERAGE_MULTIPLIER;
        require(volume <= volumeLimit, "TradePair::_openPosition: borrow limit reached");
        _registerUserVolume(maker_, volume);

        uint256 assetAmount;
        if (isShort_) {
            assetAmount = priceFeedAdapter.collateralToAssetMax(volume);
        } else {
            assetAmount = priceFeedAdapter.collateralToAssetMin(volume);
        }

        (int256 currentBorrowFeeIntegral, int256 currentFundingFeeIntegral) = _getCurrentFeeIntegrals(isShort_);

        positions[id] = Position({
            margin: margin_,
            volume: volume,
            assetAmount: assetAmount,
            pastBorrowFeeIntegral: currentBorrowFeeIntegral,
            lastBorrowFeeAmount: 0,
            pastFundingFeeIntegral: currentFundingFeeIntegral,
            lastFundingFeeAmount: 0,
            collectedFundingFeeAmount: 0,
            collectedBorrowFeeAmount: 0,
            lastFeeCalculationAt: uint48(block.timestamp),
            openedAt: uint48(block.timestamp),
            isShort: isShort_,
            owner: maker_,
            lastAlterationBlock: uint40(_getBlockNumber())
        });

        positionStats.addTotalCount(margin_, volume, assetAmount, isShort_);

        _verifyPositionsValidity(id);

        emit OpenedPosition(maker_, id, margin_, volume, assetAmount, isShort_);

        return id;
    }

    /**
     * @notice Closes A position
     * @param maker_ address of the maker of this position.
     * @param positionId_ the position id.
     */
    function closePosition(address maker_, uint256 positionId_)
        external
        onlyTradeManager
        verifyOwner(maker_, positionId_)
        syncFeesBefore
    {
        _verifyAndUpdateLastAlterationBlock(positionId_);
        _verifyPositionsValidity(positionId_);
        _closePosition(positionId_);
    }

    function _closePosition(uint256 positionId_) private {
        Position storage position = positions[positionId_];

        // Clear Buffer
        (uint256 remainingMargin, uint256 remainingBufferFee, uint256 requestLoss) = _clearBuffer(position, false);

        // Get the payout to the maker
        uint256 payoutToMaker = _getPayoutToMaker(position);

        // update aggregated values
        positionStats.removeTotalCount(position.margin, position.volume, position.assetAmount, position.isShort);

        int256 protocolPnL = int256(remainingMargin) - int256(payoutToMaker) - int256(requestLoss);

        // fee manager receives the remaining fees
        _depositBorrowFees(remainingBufferFee);

        uint256 payout = _registerProtocolPnL(protocolPnL);

        // Make sure the payout to maker does not exceed the collateral for this position made up of the remaining margin and the (possible) received loss payout
        if (payoutToMaker > payout + remainingMargin) {
            payoutToMaker = payout + remainingMargin;
        }

        if (payoutToMaker > 0) {
            _payoutToMaker(position.owner, int256(payoutToMaker), position.volume, positionId_);
        }

        (int256 currentBorrowFeeIntegral, int256 currentFundingFeeIntegral) = _getCurrentFeeIntegrals(position.isShort);

        emit RealizedPnL(
            position.owner,
            positionId_,
            _getCurrentNetPnL(position),
            position.currentBorrowFeeAmount(currentBorrowFeeIntegral),
            position.currentFundingFeeAmount(currentFundingFeeIntegral)
        );

        emit ClosedPosition(positionId_, _getCurrentPrice(position.isShort, true));

        // Finally delete position
        delete positions[positionId_];
    }

    /**
     * @notice Partially closes a position on a trade pair.
     * @param maker_ owner of the position
     * @param positionId_ id of the position
     * @param proportion_ the proportion of the position that should be closed, should respect PERCENTAGE_MULTIPLIER
     */
    function partiallyClosePosition(address maker_, uint256 positionId_, uint256 proportion_)
        external
        onlyTradeManager
        verifyOwner(maker_, positionId_)
        syncFeesBefore
        updatePositionFees(positionId_)
        onlyValidAlteration(positionId_)
    {
        _partiallyClosePosition(maker_, positionId_, proportion_);
    }

    function _partiallyClosePosition(address maker_, uint256 positionId_, uint256 proportion_) private {
        Position storage position = positions[positionId_];

        int256 payoutToMaker;

        // positionDelta saves the changes in position margin, volume and size.
        // First it gets assigned the old values, than the new values are subtracted.
        PositionDetails memory positionDelta;

        // Assign old values to positionDelta
        positionDelta.margin = position.margin;
        positionDelta.volume = position.volume;
        positionDelta.assetAmount = position.assetAmount;
        int256 realizedPnL = _getCurrentNetPnL(position);

        (int256 currentBorrowFeeIntegral, int256 currentFundingFeeIntegral) = _getCurrentFeeIntegrals(position.isShort);
        int256 realizedBorrowFeeAmount = position.currentBorrowFeeAmount(currentBorrowFeeIntegral);
        int256 realizedFundingFeeAmount = position.currentFundingFeeAmount(currentFundingFeeIntegral);

        // partially close in storage
        payoutToMaker = position.partiallyClose(_getCurrentPrice(position.isShort, true), proportion_);

        // Subtract new values from positionDelta. This way positionDelta contains the changes in position margin, volume and size.
        positionDelta.margin -= position.margin;
        positionDelta.volume -= position.volume;
        positionDelta.assetAmount -= position.assetAmount;
        realizedPnL -= _getCurrentNetPnL(position);
        realizedBorrowFeeAmount -= position.lastBorrowFeeAmount;
        realizedFundingFeeAmount -= position.lastFundingFeeAmount;

        uint256 payout = _registerProtocolPnL(-realizedPnL);

        if (payoutToMaker > int256(payout + positionDelta.margin)) {
            payoutToMaker = int256(payout + positionDelta.margin);
        }

        if (payoutToMaker > 0) {
            _payoutToMaker(maker_, int256(payoutToMaker), positionDelta.volume, positionId_);
        }

        // Use positionDelta to update positionStats
        positionStats.removeTotalCount(
            positionDelta.margin, positionDelta.volume, positionDelta.assetAmount, position.isShort
        );

        emit AlteredPosition(
            PositionAlterationType.partiallyClose,
            positionId_,
            position.lastNetMargin(),
            position.volume,
            position.assetAmount
        );

        emit RealizedPnL(maker_, positionId_, realizedPnL, realizedBorrowFeeAmount, realizedFundingFeeAmount);
    }

    /**
     * @notice Extends position with margin and leverage. Leverage determins added loan. New margin and loan get added
     * to the existing position.
     * @param maker_ Address of the position maker.
     * @param positionId_ ID of the position.
     * @param addedMargin_ Margin added to the position.
     * @param addedLeverage_ Denoted in LEVERAGE_MULTIPLIER.
     */
    function extendPosition(address maker_, uint256 positionId_, uint256 addedMargin_, uint256 addedLeverage_)
        external
        onlyTradeManager
        verifyOwner(maker_, positionId_)
        verifyLeverage(addedLeverage_)
        syncFeesBefore
        updatePositionFees(positionId_)
        onlyValidAlteration(positionId_)
        checkTotalVolumeLimit
    {
        _extendPosition(maker_, positionId_, addedMargin_, addedLeverage_);
    }

    /**
     * @notice Should have received margin from TradeManager
     * @dev extendPosition simply "adds" a "new" position on top of the existing position. The two positions get merged.
     */
    function _extendPosition(address maker_, uint256 positionId_, uint256 addedMargin_, uint256 addedLeverage_)
        private
    {
        Position storage position = positions[positionId_];

        addedMargin_ = _deductAndTransferOpenFee(maker_, addedMargin_, addedLeverage_, positionId_);

        uint256 addedVolume = addedMargin_ * addedLeverage_ / LEVERAGE_MULTIPLIER;
        _registerUserVolume(maker_, addedVolume);

        uint256 addedSize;
        if (position.isShort) {
            addedSize = priceFeedAdapter.collateralToAssetMax(addedVolume);
        } else {
            addedSize = priceFeedAdapter.collateralToAssetMin(addedVolume);
        }

        // Update tally.
        positionStats.addTotalCount(addedMargin_, addedVolume, addedSize, position.isShort);

        // Update position.
        position.extend(addedMargin_, addedSize, addedVolume);

        emit AlteredPosition(
            PositionAlterationType.extend, positionId_, position.lastNetMargin(), position.volume, position.assetAmount
        );
    }

    /**
     * @notice Extends position with loan to target leverage.
     * @param maker_ Address of the position maker.
     * @param positionId_ ID of the position.
     * @param targetLeverage_ Target leverage in respect to LEVERAGE_MULTIPLIER.
     */
    function extendPositionToLeverage(address maker_, uint256 positionId_, uint256 targetLeverage_)
        external
        onlyTradeManager
        verifyOwner(maker_, positionId_)
        syncFeesBefore
        updatePositionFees(positionId_)
        onlyValidAlteration(positionId_)
        verifyLeverage(targetLeverage_)
        checkTotalVolumeLimit
    {
        _extendPositionToLeverage(positionId_, targetLeverage_);
    }

    function _extendPositionToLeverage(uint256 positionId_, uint256 targetLeverage_) private {
        Position storage position = positions[positionId_];

        int256 currentPrice = _getCurrentPrice(position.isShort, false);

        // Old values are needed to calculate the differences of aggregated values
        uint256 old_margin = position.margin;
        uint256 old_volume = position.volume;
        uint256 old_size = position.assetAmount;

        // The user does not deposit fee with this transaction, so the fee is taken from the margin of the position
        position.margin = _deductAndTransferExtendToLeverageFee(
            position.owner, position.margin, position.currentVolume(currentPrice), targetLeverage_, positionId_
        );

        // update position in storage
        position.extendToLeverage(currentPrice, targetLeverage_);

        // update aggregated values
        _registerUserVolume(position.owner, position.volume - old_volume);
        positionStats.addTotalCount(0, position.volume - old_volume, position.assetAmount - old_size, position.isShort);

        positionStats.removeTotalCount(old_margin - position.margin, 0, 0, position.isShort);

        emit AlteredPosition(
            PositionAlterationType.extendToLeverage,
            positionId_,
            position.lastNetMargin(),
            position.volume,
            position.assetAmount
        );
    }

    /**
     * @notice Removes margin from a position
     * @param maker_ owner of the position
     * @param positionId_ id of the position
     * @param removedMargin_ the margin to be removed
     */
    function removeMarginFromPosition(address maker_, uint256 positionId_, uint256 removedMargin_)
        external
        onlyTradeManager
        verifyOwner(maker_, positionId_)
        syncFeesBefore
        updatePositionFees(positionId_)
        onlyValidAlteration(positionId_)
    {
        _removeMarginFromPosition(maker_, positionId_, removedMargin_);
    }

    function _removeMarginFromPosition(address maker_, uint256 positionId_, uint256 removedMargin_) private {
        Position storage position = positions[positionId_];

        // update position in storage
        position.removeMargin(removedMargin_);

        // The minMargin condition has to hold after the margin is removed
        require(
            position.lastNetMargin() >= minMargin,
            "TradePair::_removeMarginFromPosition: Margin must be above minMargin"
        );

        // update aggregated values
        positionStats.removeTotalCount(removedMargin_, 0, 0, position.isShort);

        _payoutToMaker(maker_, int256(removedMargin_), 0, positionId_);

        emit AlteredPosition(
            PositionAlterationType.removeMargin,
            positionId_,
            position.lastNetMargin(),
            position.volume,
            position.assetAmount
        );
    }

    /**
     * @notice Adds margin to a position
     * @param maker_ owner of the position
     * @param positionId_ id of the position
     * @param addedMargin_ the margin to be added
     */
    function addMarginToPosition(address maker_, uint256 positionId_, uint256 addedMargin_)
        external
        onlyTradeManager
        verifyOwner(maker_, positionId_)
        syncFeesBefore
        updatePositionFees(positionId_)
        onlyValidAlteration(positionId_)
    {
        _addMarginToPosition(maker_, positionId_, addedMargin_);
    }

    /**
     * @dev Should have received margin from TradeManager
     */
    function _addMarginToPosition(address maker_, uint256 positionId_, uint256 addedMargin_) private {
        Position storage position = positions[positionId_];

        addedMargin_ = _deductAndTransferOpenFee(maker_, addedMargin_, LEVERAGE_MULTIPLIER, positionId_);

        // change position in storage
        position.addMargin(addedMargin_);

        // The maxLeverage condition has to hold
        require(
            position.lastNetLeverage() >= minLeverage,
            "TradePair::_addMarginToPosition: Leverage must be above minLeverage"
        );

        // update aggregated values
        positionStats.addTotalCount(addedMargin_, 0, 0, position.isShort);

        emit AlteredPosition(
            PositionAlterationType.addMargin,
            positionId_,
            position.lastNetMargin(),
            position.volume,
            position.assetAmount
        );
    }

    /**
     * @notice Liquidates position and sends liquidation reward to msg.sender
     * @param liquidator_ Address of the liquidator.
     * @param positionId_ position id
     */
    function liquidatePosition(address liquidator_, uint256 positionId_)
        external
        onlyTradeManager
        onlyLiquidatable(positionId_)
        syncFeesBefore
    {
        _verifyAndUpdateLastAlterationBlock(positionId_);
        _liquidatePosition(liquidator_, positionId_);
    }

    /**
     * @notice liquidates a position
     */
    function _liquidatePosition(address liquidator_, uint256 positionId_) private {
        Position storage position = positions[positionId_];

        // Clear Buffer
        (uint256 remainingMargin, uint256 remainingBufferFee, uint256 requestLoss) = _clearBuffer(position, true);

        // Get the payout to the maker
        uint256 payoutToMaker = _getPayoutToMaker(position);

        // Calculate the protocol PnL
        int256 protocolPnL = int256(remainingMargin) - int256(payoutToMaker) - int256(requestLoss);

        // Register the protocol PnL and receive a possible payout
        uint256 payout = _registerProtocolPnL(protocolPnL);

        // Calculate the available liquidity for this position's liquidation
        uint256 availableLiquidity = remainingBufferFee + payout + uint256(liquidatorReward);

        // Prio 1: Keep the request loss at TradePair, as this makes up the funding fee that pays the other positions
        if (availableLiquidity > requestLoss) {
            availableLiquidity -= requestLoss;
        } else {
            // If available liquidity is not enough to cover the requested loss,
            // emit a warning, because the liquidity pools are drained.
            requestLoss = availableLiquidity;
            emit LiquidityGapWarning(requestLoss);
            availableLiquidity = 0;
        }

        // Prio 2: Pay out the liquidator reward
        if (availableLiquidity > liquidatorReward) {
            _payOut(liquidator_, liquidatorReward);
            availableLiquidity -= liquidatorReward;
        } else {
            _payOut(liquidator_, availableLiquidity);
            availableLiquidity = 0;
        }

        // Prio 3: Pay out to the maker
        if (availableLiquidity > payoutToMaker) {
            _payoutToMaker(position.owner, int256(payoutToMaker), position.volume, positionId_);
            availableLiquidity -= payoutToMaker;
        } else {
            _payoutToMaker(position.owner, int256(availableLiquidity), position.volume, positionId_);
            availableLiquidity = 0;
        }

        // Prio 4: Pay out the buffered fee
        if (availableLiquidity > remainingBufferFee) {
            _depositBorrowFees(remainingBufferFee);
            availableLiquidity -= remainingBufferFee;
        } else {
            _depositBorrowFees(availableLiquidity);
            availableLiquidity = 0;
        }
        // Now, available liquity is zero

        // Remove position from total counts
        positionStats.removeTotalCount(position.margin, position.volume, position.assetAmount, position.isShort);

        (int256 currentBorrowFeeIntegral, int256 currentFundingFeeIntegral) = _getCurrentFeeIntegrals(position.isShort);

        emit RealizedPnL(
            position.owner,
            positionId_,
            _getCurrentNetPnL(position),
            position.currentBorrowFeeAmount(currentBorrowFeeIntegral),
            position.currentFundingFeeAmount(currentFundingFeeIntegral)
        );

        emit LiquidatedPosition(positionId_, liquidator_);

        // Delete Position
        delete positions[positionId_];
    }

    /* ========== HELPER FUNCTIONS ========= */

    /**
     * @notice Calculates outstanding borrow fees, transfers it to FeeManager and updates the fee integrals.
     * Funding fee stays at this TradePair as it is transfered virtually to the opposite positions ("long pays short").
     *
     * All positions' margins make up the trade pair's balance of which the fee is transfered from.
     * @dev This function is public to allow possible fee syncing in periods without trades.
     */
    function syncPositionFees() public {
        // The total amount of borrow fee is based on the entry volume of all positions
        // This is done to batch collect borrow fees for all open positions

        uint256 timeSinceLastUpdate = block.timestamp - feeIntegral.lastUpdatedAt;

        if (timeSinceLastUpdate > 0) {
            int256 elapsedBorrowFeeIntegral = feeIntegral.getElapsedBorrowFeeIntegral();
            uint256 totalVolume = positionStats.totalShortVolume + positionStats.totalLongVolume;

            int256 newBorrowFeeAmount = elapsedBorrowFeeIntegral * int256(totalVolume) / FEE_MULTIPLIER;

            // Fee Integrals get updated for funding fee.
            feeIntegral.update(positionStats.totalLongAssetAmount, positionStats.totalShortAssetAmount);

            emit UpdatedFeeIntegrals(
                feeIntegral.borrowFeeIntegral, feeIntegral.longFundingFeeIntegral, feeIntegral.shortFundingFeeIntegral
            );

            // Reduce by the fee buffer
            // Buffer is used to prevent overrtaking the fees from the position
            uint256 reducedFeeAmount = feeBuffer.takeBufferFrom(uint256(newBorrowFeeAmount));

            // Transfer borrow fee to FeeManager
            _depositBorrowFees(reducedFeeAmount);
        }
    }

    /**
     * @notice Clears the fee buffer and returns the remaining margin, remaining buffer fee and request loss.
     * @param position_ The position to clear the buffer for.
     * @param isLiquidation_ Whether the buffer is cleared due to a liquidation. In this case, liquidatorReward is added to funding fee.
     * @return remainingMargin the _margin of the position after clearing the buffer and paying fees
     * @return remainingBuffer remaining amount that needs to be transferred to the fee manager
     * @return requestLoss the amount of loss that needs to be requested from the liquidity pool
     */
    function _clearBuffer(Position storage position_, bool isLiquidation_)
        private
        returns (uint256, uint256, uint256)
    {
        (int256 currentBorrowFeeIntegral, int256 currentFundingFeeIntegral) = _getCurrentFeeIntegrals(position_.isShort);

        uint256 additionalFee = isLiquidation_ ? liquidatorReward : 0;

        // Clear Buffer
        return feeBuffer.clearBuffer(
            position_.margin,
            position_.currentBorrowFeeAmount(currentBorrowFeeIntegral) + position_.collectedBorrowFeeAmount,
            position_.currentFundingFeeAmount(currentFundingFeeIntegral) + position_.collectedFundingFeeAmount
                + int256(additionalFee)
        );
    }

    /**
     * @notice updates the fee of this position. Necessary before changing its volume.
     * @param positionId_ the id of the position
     */
    function _updatePositionFees(uint256 positionId_) internal {
        Position storage position = positions[positionId_];
        (int256 currentBorrowFeeIntegral, int256 currentFundingFeeIntegral) = _getCurrentFeeIntegrals(position.isShort);

        position.updateFees(currentBorrowFeeIntegral, currentFundingFeeIntegral);

        emit UpdatedFeesOfPosition(
            positionId_, position.lastBorrowFeeAmount + position.lastFundingFeeAmount, position.lastNetMargin()
        );
    }

    /**
     * @notice Registers profit or loss at liquidity pool adapter
     * @param protocolPnL_ Profit or loss of protocol
     * @return payout Payout received from the liquidity pool adapter
     */
    function _registerProtocolPnL(int256 protocolPnL_) internal returns (uint256 payout) {
        if (protocolPnL_ > 0) {
            // Profit
            collateral.safeTransfer(address(liquidityPoolAdapter), uint256(protocolPnL_));
            liquidityPoolAdapter.depositProfit(uint256(protocolPnL_));
        } else if (protocolPnL_ < 0) {
            // Loss
            payout = liquidityPoolAdapter.requestLossPayout(uint256(-protocolPnL_));
        }
        // if PnL == 0, nothing happens

        emit RegisteredProtocolPnL(protocolPnL_, payout);
    }

    /**
     * @notice Pays out amount to receiver. If balance does not suffice, registers loss.
     * @param receiver_ Address of receiver.
     * @param amount_ Amount to pay out.
     */
    function _payOut(address receiver_, uint256 amount_) internal {
        if (amount_ > collateral.balanceOf(address(this))) {
            liquidityPoolAdapter.requestLossPayout(amount_ - collateral.balanceOf(address(this)));
        }
        collateral.safeTransfer(receiver_, amount_);
    }

    /**
     * @dev Deducts fees from the given amount and pays the rest to maker
     */
    function _payoutToMaker(address maker_, int256 amount_, uint256 closedVolume, uint256 positionId_) private {
        if (amount_ > 0) {
            uint256 closePositionFee = feeManager.calculateUserCloseFeeAmount(maker_, closedVolume);
            _depositClosePositionFees(maker_, closePositionFee, positionId_);

            uint256 reducedAmount;
            if (uint256(amount_) > closePositionFee) {
                reducedAmount = uint256(amount_) - closePositionFee;
            }

            _payOut(maker_, reducedAmount);

            emit PayedOutCollateral(maker_, reducedAmount, positionId_);
        }
    }

    /**
     * @notice Deducts open position fee for a given margin and leverage. Returns the margin after fee deduction.
     * @dev The fee is exactly [userFee] of the resulting volume.
     * @param margin_ The margin of the position.
     * @param leverage_ The leverage of the position.
     * @return marginAfterFee_ The margin after fee deduction.
     */
    function _deductAndTransferOpenFee(address maker_, uint256 margin_, uint256 leverage_, uint256 positionId_)
        internal
        returns (uint256 marginAfterFee_)
    {
        uint256 openPositionFee = feeManager.calculateUserOpenFeeAmount(maker_, margin_, leverage_);
        _depositOpenPositionFees(maker_, openPositionFee, positionId_);

        marginAfterFee_ = margin_ - openPositionFee;
    }

    /**
     * @notice Deducts open position fee for a given margin and leverage. Returns the margin after fee deduction.
     * @dev The fee is exactly [userFee] of the resulting volume.
     * @param maker_ The maker of the position.
     * @param margin_ The margin of the position.
     * @param volume_ The volume of the position.
     * @param targetLeverage_ The target leverage of the position.
     * @param positionId_ The id of the position.
     * @return marginAfterFee_ The margin after fee deduction.
     */
    function _deductAndTransferExtendToLeverageFee(
        address maker_,
        uint256 margin_,
        uint256 volume_,
        uint256 targetLeverage_,
        uint256 positionId_
    ) internal returns (uint256 marginAfterFee_) {
        uint256 openPositionFee =
            feeManager.calculateUserExtendToLeverageFeeAmount(maker_, margin_, volume_, targetLeverage_);
        _depositOpenPositionFees(maker_, openPositionFee, positionId_);

        marginAfterFee_ = margin_ - openPositionFee;
    }

    /**
     * @notice Registers user volume in USD.
     * @dev Trimms decimals from USD value.
     *
     * @param user_ User address.
     * @param volume_ Volume in collateral.
     */
    function _registerUserVolume(address user_, uint256 volume_) private {
        uint256 volumeUsd = priceFeedAdapter.collateralToUsdMin(volume_);

        uint40 volumeUsdTrimmed = uint40(volumeUsd / USD_TRIM);

        userManager.addUserVolume(user_, volumeUsdTrimmed);
    }

    /**
     * @dev Deposits the open position fees to the FeeManager.
     */
    function _depositOpenPositionFees(address user_, uint256 amount_, uint256 positionId_) private {
        _resetApprove(address(feeManager), amount_);
        feeManager.depositOpenFees(user_, address(collateral), amount_, positionIdToWhiteLabel[positionId_]);

        emit DepositedOpenFees(user_, amount_, positionId_);
    }

    /**
     * @dev Deposits the close position fees to the FeeManager.
     */
    function _depositClosePositionFees(address user_, uint256 amount_, uint256 positionId_) private {
        _resetApprove(address(feeManager), amount_);
        feeManager.depositCloseFees(user_, address(collateral), amount_, positionIdToWhiteLabel[positionId_]);

        emit DepositedCloseFees(user_, amount_, positionId_);
    }

    /**
     * @dev Deposits the borrow fees to the FeeManager
     */
    function _depositBorrowFees(uint256 amount_) private {
        if (amount_ > 0) {
            _resetApprove(address(feeManager), amount_);
            feeManager.depositBorrowFees(address(collateral), amount_);
        }

        emit DepositedBorrowFees(amount_);
    }

    /**
     * @dev Sets the allowance on the collateral to 0.
     */
    function _resetApprove(address user_, uint256 amount_) private {
        if (collateral.allowance(address(this), user_) > 0) {
            collateral.safeApprove(user_, 0);
        }

        collateral.safeApprove(user_, amount_);
    }

    /* ========== EXTERNAL VIEW FUNCTIONS ========== */

    /**
     * @notice Multiplier from collateral to price.
     * @return collateralToPriceMultiplier
     */
    function collateralToPriceMultiplier() external view returns (uint256) {
        return _collateralToPriceMultiplier;
    }

    /**
     * @notice Calculates the current funding fee rates
     * @return longFundingFeeRate long funding fee rate
     * @return shortFundingFeeRate short funding fee rate
     */
    function getCurrentFundingFeeRates()
        external
        view
        returns (int256 longFundingFeeRate, int256 shortFundingFeeRate)
    {
        return feeIntegral.getCurrentFundingFeeRates(
            positionStats.totalLongAssetAmount, positionStats.totalShortAssetAmount
        );
    }

    /**
     * @notice returns the details of a position
     * @dev returns PositionDetails
     */
    function detailsOfPosition(uint256 positionId_) external view returns (PositionDetails memory) {
        Position storage position = positions[positionId_];
        require(position.exists(), "TradePair::detailsOfPosition: Position does not exist");

        // Fee integrals
        (int256 currentBorrowFeeIntegral, int256 currentFundingFeeIntegral) = _getCurrentFeeIntegrals(position.isShort);

        uint256 maintenanceMargin =
            absoluteMaintenanceMargin() + feeManager.calculateUserCloseFeeAmount(position.owner, position.volume);

        // Construnct position info
        PositionDetails memory positionDetails;
        positionDetails.id = positionId_;
        positionDetails.margin = position.currentNetMargin(currentBorrowFeeIntegral, currentFundingFeeIntegral);
        positionDetails.volume = position.volume;
        positionDetails.assetAmount = position.assetAmount;
        positionDetails.isShort = position.isShort;
        positionDetails.leverage = position.currentNetLeverage(currentBorrowFeeIntegral, currentFundingFeeIntegral);
        positionDetails.entryPrice = position.entryPrice();
        positionDetails.liquidationPrice =
            position.liquidationPrice(currentBorrowFeeIntegral, currentFundingFeeIntegral, maintenanceMargin);
        positionDetails.currentBorrowFeeAmount = position.currentBorrowFeeAmount(currentBorrowFeeIntegral);
        positionDetails.currentFundingFeeAmount = position.currentFundingFeeAmount(currentFundingFeeIntegral);
        return positionDetails;
    }

    /**
     * @notice Returns if a position is liquidatable
     * @param positionId_ the position id
     */
    function positionIsLiquidatable(uint256 positionId_) external view returns (bool) {
        return _positionIsLiquidatable(positionId_);
    }

    /**
     * @notice Simulates if a position is liquidatable at a given price. Meant to be used by external liquidation services.
     * @param positionId_ the position id
     * @param price_ the price to simulate
     */
    function positionIsLiquidatableAtPrice(uint256 positionId_, int256 price_) external view returns (bool) {
        Position storage position = positions[positionId_];
        require(position.exists(), "TradePair::positionIsLiquidatableAtPrice: position does not exist");
        (int256 currentBorrowFeeIntegral, int256 currentFundingFeeIntegral) = _getCurrentFeeIntegrals(position.isShort);

        // Maintenance margin is the absolute maintenance margin plus the fee for closing the position
        uint256 maintenanceMargin =
            absoluteMaintenanceMargin() + feeManager.calculateUserCloseFeeAmount(position.owner, position.volume);

        return position.isLiquidatable(price_, currentBorrowFeeIntegral, currentFundingFeeIntegral, maintenanceMargin);
    }

    /**
     * @notice Returns if the position is short
     * @param positionId_ the position id
     * @return isShort_ true if the position is short
     */
    function positionIsShort(uint256 positionId_) external view returns (bool) {
        return positions[positionId_].isShort;
    }

    /**
     * @notice Returns the current min and max price
     */
    function getCurrentPrices() external view returns (int256, int256) {
        return (priceFeedAdapter.markPriceMin(), priceFeedAdapter.markPriceMax());
    }

    /**
     * @notice returns absolute maintenance margin
     * @dev Currently only the liquidator reward is the absolute maintenance margin, but this could change in the future
     * @return absoluteMaintenanceMargin
     */
    function absoluteMaintenanceMargin() public view returns (uint256) {
        return liquidatorReward;
    }

    /* ========== ADMIN FUNCTIONS ========== */

    /**
     * @notice Sets the basis hourly borrow fee
     * @param borrowFeeRate_ should be in FEE_DECIMALS and per hour
     */
    function setBorrowFeeRate(int256 borrowFeeRate_) public onlyOwner syncFeesBefore {
        feeIntegral.borrowFeeRate = int256(borrowFeeRate_);

        emit SetBorrowFeeRate(borrowFeeRate_);
    }

    /**
     * @notice Sets the surplus fee
     * @param maxFundingFeeRate_ should be in FEE_DECIMALS and per hour
     */
    function setMaxFundingFeeRate(int256 maxFundingFeeRate_) public onlyOwner syncFeesBefore {
        feeIntegral.fundingFeeRate = maxFundingFeeRate_;

        emit SetMaxFundingFeeRate(maxFundingFeeRate_);
    }

    /**
     * @notice Sets the max excess ratio at which the full funding fee is charged
     * @param maxExcessRatio_ should be denominated by FEE_MULTIPLER
     */
    function setMaxExcessRatio(int256 maxExcessRatio_) public onlyOwner syncFeesBefore {
        feeIntegral.maxExcessRatio = maxExcessRatio_;

        emit SetMaxExcessRatio(maxExcessRatio_);
    }

    /**
     * @notice Sets the liquidator reward
     * @param liquidatorReward_ in collateral decimals
     */
    function setLiquidatorReward(uint256 liquidatorReward_) public onlyOwner {
        liquidatorReward = liquidatorReward_;

        emit SetLiquidatorReward(liquidatorReward_);
    }

    /**
     * @notice Sets the minimum leverage
     * @param minLeverage_ in respect to LEVERAGE_MULTIPLIER
     */
    function setMinLeverage(uint128 minLeverage_) public onlyOwner {
        require(minLeverage_ >= MIN_LEVERAGE, "TradePair::setMinLeverage: Leverage too small");
        minLeverage = minLeverage_;

        emit SetMinLeverage(minLeverage_);
    }

    /**
     * @notice Sets the maximum leverage
     * @param maxLeverage_ in respect to LEVERAGE_MULTIPLIER
     */
    function setMaxLeverage(uint128 maxLeverage_) public onlyOwner {
        require(maxLeverage_ <= MAX_LEVERAGE, "TradePair::setMaxLeverage: Leverage to high");
        maxLeverage = maxLeverage_;

        emit SetMaxLeverage(maxLeverage_);
    }

    /**
     * @notice Sets the minimum margin
     * @param minMargin_ in collateral decimals
     */
    function setMinMargin(uint256 minMargin_) public onlyOwner {
        minMargin = minMargin_;

        emit SetMinMargin(minMargin_);
    }

    /**
     * @notice Sets the borrow limit
     * @param volumeLimit_ in collateral decimals
     */
    function setVolumeLimit(uint256 volumeLimit_) public onlyOwner {
        volumeLimit = volumeLimit_;

        emit SetVolumeLimit(volumeLimit_);
    }

    /**
     * @notice Sets the factor for the fee buffer. Denominated by BUFFER_MULTIPLIER
     * @param feeBufferFactor_ the factor for the fee buffer
     */
    function setFeeBufferFactor(int256 feeBufferFactor_) public onlyOwner syncFeesBefore {
        feeBuffer.bufferFactor = feeBufferFactor_;

        emit SetFeeBufferFactor(feeBufferFactor_);
    }

    /**
     * @notice Sets the total volume limit for both long and short positions
     * @param totalVolumeLimit_ total volume limit
     */
    function setTotalVolumeLimit(uint256 totalVolumeLimit_) public onlyOwner {
        totalVolumeLimit = totalVolumeLimit_;
        emit SetTotalVolumeLimit(totalVolumeLimit_);
    }

    /**
     * @notice Sets the price feed adapter
     * @param priceFeedAdapter_ IPriceFeedAdapter
     * @dev PriceFeedAdapter checks that asset and collateral decimals are less or equal than price decimals,
     * So they can be savely used here.
     */
    function setPriceFeedAdapter(IPriceFeedAdapter priceFeedAdapter_) public onlyOwner {
        // Set Decimals

        // Calculate Multipliers
        _collateralToPriceMultiplier = PRICE_MULTIPLIER / (10 ** priceFeedAdapter_.collateralDecimals());

        // Set PriceFeedAdapter
        priceFeedAdapter = priceFeedAdapter_;
        emit SetPriceFeedAdapter(address(priceFeedAdapter_));
    }

    /* ========== INTERNAL VIEW FUNCTIONS ========== */

    /**
     * @notice Returns the payout to the maker of this position
     * @param position_ the position to calculate the payout for
     * @return the payout to the maker of this position
     */
    function _getPayoutToMaker(Position storage position_) private view returns (uint256) {
        (int256 currentBorrowFeeIntegral, int256 currentFundingFeeIntegral) = _getCurrentFeeIntegrals(position_.isShort);

        int256 netEquity = position_.currentNetEquity(
            _getCurrentPrice(position_.isShort, true), currentBorrowFeeIntegral, currentFundingFeeIntegral
        );
        return netEquity > 0 ? uint256(netEquity) : 0;
    }

    /**
     * @notice Returns the current price
     * @param position_ the position to calculate the price for
     * @return the current price
     */
    function _getCurrentNetPnL(Position storage position_) private view returns (int256) {
        (int256 currentBorrowFeeIntegral, int256 currentFundingFeeIntegral) = _getCurrentFeeIntegrals(position_.isShort);

        return position_.currentNetPnL(
            _getCurrentPrice(position_.isShort, true), currentBorrowFeeIntegral, currentFundingFeeIntegral
        );
    }

    /**
     * @dev Returns borrow and funding fee intagral for long or short position
     */
    function _getCurrentFeeIntegrals(bool isShort_) internal view returns (int256, int256) {
        // Funding fee integrals differ for short and long positions
        (int256 longFeeIntegral, int256 shortFeeIntegral) = feeIntegral.getCurrentFundingFeeIntegrals(
            positionStats.totalLongAssetAmount, positionStats.totalShortAssetAmount
        );
        int256 currentFundingFeeIntegral = isShort_ ? shortFeeIntegral : longFeeIntegral;

        // Borrow fee integrals are the same for short and long positions
        int256 currentBorrowFeeIntegral = feeIntegral.getCurrentBorrowFeeIntegral();

        // Return the current fee integrals
        return (currentBorrowFeeIntegral, currentFundingFeeIntegral);
    }

    /**
     * @notice Returns if a position is liquidatable
     * @param positionId_ the position id
     */
    function _positionIsLiquidatable(uint256 positionId_) internal view returns (bool) {
        Position storage position = positions[positionId_];
        require(position.exists(), "TradePair::_positionIsLiquidatable: position does not exist");
        (int256 currentBorrowFeeIntegral, int256 currentFundingFeeIntegral) = _getCurrentFeeIntegrals(position.isShort);

        // Maintenance margin is the absolute maintenance margin plus the fee for closing the position
        uint256 maintenanceMargin =
            absoluteMaintenanceMargin() + feeManager.calculateUserCloseFeeAmount(position.owner, position.volume);

        return position.isLiquidatable(
            _getCurrentPrice(position.isShort, true),
            currentBorrowFeeIntegral,
            currentFundingFeeIntegral,
            maintenanceMargin
        );
    }

    /**
     * @notice Returns current price depending on the direction of the trade and if is buying or selling
     * @param isShort_ bool if the position is short
     * @param isDecreasingPosition_ true on closing and decreasing the position. False on open and extending.
     */
    function _getCurrentPrice(bool isShort_, bool isDecreasingPosition_) internal view returns (int256) {
        if (isShort_ == isDecreasingPosition_) {
            // buy long, sell short
            // get maxprice
            return priceFeedAdapter.markPriceMax();
        } else {
            // buy short, sell long
            // get minprice
            return priceFeedAdapter.markPriceMin();
        }
    }

    /* ========== RESTRICTION FUNCTIONS ========== */

    /**
     * @dev Reverts when sender is not the TradeManager
     */
    function _onlyTradeManager() private view {
        require(msg.sender == address(tradeManager), "TradePair::_onlyTradeManager: only TradeManager");
    }

    /**
     * @dev Reverts when either long or short positions extend the total volume limit
     */
    function _checkTotalVolumeLimitAfter() private view {
        require(
            positionStats.totalLongVolume <= totalVolumeLimit,
            "TradePair::_checkTotalVolumeLimitAfter: total volume limit reached by long positions"
        );
        require(
            positionStats.totalShortVolume <= totalVolumeLimit,
            "TradePair::_checkTotalVolumeLimitAfter: total volume limit reached by short positions"
        );
    }

    /**
     * @notice Verifies that the position did not get altered this block and updates lastAlterationBlock of this position.
     * @dev Positions must not be altered at the same block. This reduces that risk of sandwich attacks.
     */
    function _verifyAndUpdateLastAlterationBlock(uint256 positionId_) private {
        require(
            positions[positionId_].lastAlterationBlock < _getBlockNumber(),
            "TradePair::_verifyAndUpdateLastAlterationBlock: position already altered this block"
        );
        positions[positionId_].lastAlterationBlock = uint40(_getBlockNumber());
    }

    /**
     * @notice Checks if the position is valid:
     *
     * - The position must exists
     * - The position must not be liquidatable
     * - The position must not reach the volume limit
     * - The position must not reach the leverage limits
     */
    function _verifyPositionsValidity(uint256 positionId_) private view {
        Position storage _position = positions[positionId_];

        // Position must exist
        require(_position.exists(), "TradePair::_verifyPositionsValidity: position does not exist");

        // Position must not be liquidatable
        {
            (int256 currentBorrowFeeIntegral, int256 currentFundingFeeIntegral) =
                _getCurrentFeeIntegrals(_position.isShort);
            require(
                !_position.isLiquidatable(
                    _getCurrentPrice(_position.isShort, true),
                    currentBorrowFeeIntegral,
                    currentFundingFeeIntegral,
                    absoluteMaintenanceMargin()
                ),
                "TradePair::_verifyPositionsValidity: position would be liquidatable"
            );
        }

        // Position must not reach the volume limit
        {
            require(
                _position.currentVolume(_getCurrentPrice(_position.isShort, false)) <= volumeLimit,
                "TradePair_verifyPositionsValidity: Borrow limit reached"
            );
        }

        // The position must not reach the leverage limits
        _verifyLeverage(_position.lastNetLeverage());
    }

    /**
     * @dev Reverts when leverage is out of bounds
     */
    function _verifyLeverage(uint256 leverage_) private view {
        // We add/subtract 1 to the limits to account for rounding errors
        require(
            leverage_ >= minLeverage - 1, "TradePair::_verifyLeverage: leverage must be above or equal min leverage"
        );
        require(leverage_ <= maxLeverage, "TradePair::_verifyLeverage: leverage must be under or equal max leverage");
    }

    function _verifyOwner(address maker_, uint256 positionId_) private view {
        require(positions[positionId_].owner == maker_, "TradePair::_verifyOwner: not the owner");
    }

    /* ========== MODIFIERS ========== */

    /**
     * @dev updates the fee collected fees of this position. Necessary before changing its volume.
     * @param positionId_ the id of the position
     */
    modifier updatePositionFees(uint256 positionId_) {
        _updatePositionFees(positionId_);
        _;
    }

    /**
     * @dev collects fees by transferring them to the FeeManager
     */
    modifier syncFeesBefore() {
        syncPositionFees();
        _;
    }

    /**
     * @dev reverts when position is not liquidatable
     */
    modifier onlyLiquidatable(uint256 positionId_) {
        require(_positionIsLiquidatable(positionId_), "TradePair::onlyLiquidatable: position is not liquidatable");
        _;
    }

    /**
     * @dev Reverts when aggregated size reaches asset amount limit after transaction
     */
    modifier checkTotalVolumeLimit() {
        _;
        _checkTotalVolumeLimitAfter();
    }

    /**
     * @notice Checks if the alteration is valid. Alteration is valid, when:
     *
     * - The position did not get altered at this block
     * - The position is not liquidatable after the alteration
     */
    modifier onlyValidAlteration(uint256 positionId_) {
        _verifyAndUpdateLastAlterationBlock(positionId_);
        _;
        _verifyPositionsValidity(positionId_);
    }

    /**
     * @dev verifies that leverage is in bounds
     */
    modifier verifyLeverage(uint256 leverage_) {
        _verifyLeverage(leverage_);
        _;
    }

    /**
     * @dev Verfies that sender is the owner of the position
     */
    modifier verifyOwner(address maker_, uint256 positionId_) {
        _verifyOwner(maker_, positionId_);
        _;
    }

    /**
     * @dev Verfies that TradeManager sent the transactions
     */
    modifier onlyTradeManager() {
        _onlyTradeManager();
        _;
    }
}

