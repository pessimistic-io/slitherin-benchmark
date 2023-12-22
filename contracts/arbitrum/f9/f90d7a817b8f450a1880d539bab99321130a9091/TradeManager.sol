// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.17;

import "./SafeERC20.sol";
import "./IController.sol";
import "./ITradeManager.sol";
import "./ITradePair.sol";
import "./IUpdatable.sol";
import "./IUserManager.sol";

/**
 * @notice Indicates if the min or max price should be used. Depends on LONG or SHORT and buy or sell.
 * @custom:value MIN (0) indicates that the min price should be used
 * @custom:value MAX (1) indicates that the max price should be used
 */
enum UsePrice {
    MIN,
    MAX
}

/**
 * @title TradeManager
 * @notice Facilitates trading on trading pairs.
 */
contract TradeManager is ITradeManager {
    using SafeERC20 for IERC20;
    /* ========== STATE VARIABLES ========== */

    IController public immutable controller;
    IUserManager public immutable userManager;

    /* ========== CONSTRUCTOR ========== */

    /**
     * @notice Constructs the TradeManager contract.
     * @param controller_ The address of the controller.
     * @param userManager_ The address of the user manager.
     */
    constructor(IController controller_, IUserManager userManager_) {
        require(address(controller_) != address(0), "TradeManager::constructor: controller is 0 address");

        controller = controller_;
        userManager = userManager_;
    }

    /* ========== TRADING FUNCTIONS ========== */

    /**
     * @notice Opens a position for a trading pair.
     * @param params_ The parameters for opening a position.
     * @param maker_ Maker of the position
     */
    function _openPosition(OpenPositionParams memory params_, address maker_) internal returns (uint256) {
        ITradePair(params_.tradePair).collateral().safeTransferFrom(maker_, address(params_.tradePair), params_.margin);

        userManager.setUserReferrer(maker_, params_.referrer);

        uint256 id = ITradePair(params_.tradePair).openPosition(
            maker_, params_.margin, params_.leverage, params_.isShort, params_.whitelabelAddress
        );

        emit PositionOpened(params_.tradePair, id);

        return id;
    }

    /**
     * @notice Closes a position for a trading pair.
     *
     * @param params_ The parameters for closing the position.
     * @param maker_ Maker of the position
     */
    function _closePosition(ClosePositionParams memory params_, address maker_) internal {
        ITradePair(params_.tradePair).closePosition(maker_, params_.positionId);
        emit PositionClosed(params_.tradePair, params_.positionId);
    }

    /**
     * @notice Partially closes a position on a trade pair.
     * @param params_ The parameters for partially closing the position.
     * @param maker_ Maker of the position
     */
    function _partiallyClosePosition(PartiallyClosePositionParams memory params_, address maker_) internal {
        ITradePair(params_.tradePair).partiallyClosePosition(maker_, params_.positionId, params_.proportion);
        emit PositionPartiallyClosed(params_.tradePair, params_.positionId, params_.proportion);
    }

    /**
     * @notice Removes margin from a position
     * @param params_ The parameters for removing margin from the position.
     * @param maker_ Maker of the position
     */
    function _removeMarginFromPosition(RemoveMarginFromPositionParams memory params_, address maker_) internal {
        ITradePair(params_.tradePair).removeMarginFromPosition(maker_, params_.positionId, params_.removedMargin);

        emit MarginRemovedFromPosition(params_.tradePair, params_.positionId, params_.removedMargin);
    }

    /**
     * @notice Adds margin to a position
     * @param params_ The parameters for adding margin to the position.
     * @param maker_ Maker of the position
     */
    function _addMarginToPosition(AddMarginToPositionParams memory params_, address maker_) internal {
        // Transfer Collateral to TradePair
        ITradePair(params_.tradePair).collateral().safeTransferFrom(
            maker_, address(params_.tradePair), params_.addedMargin
        );

        ITradePair(params_.tradePair).addMarginToPosition(maker_, params_.positionId, params_.addedMargin);

        emit MarginAddedToPosition(params_.tradePair, params_.positionId, params_.addedMargin);
    }

    /**
     * @notice Extends position with margin and loan.
     * @param params_ The parameters for extending the position.
     * @param maker_ Maker of the position
     */
    function _extendPosition(ExtendPositionParams memory params_, address maker_) internal {
        // Transfer Collateral to TradePair
        ITradePair(params_.tradePair).collateral().safeTransferFrom(
            maker_, address(params_.tradePair), params_.addedMargin
        );

        ITradePair(params_.tradePair).extendPosition(
            maker_, params_.positionId, params_.addedMargin, params_.addedLeverage
        );

        emit PositionExtended(params_.tradePair, params_.positionId, params_.addedMargin, params_.addedLeverage);
    }

    /**
     * @notice Extends position with loan to target leverage.
     * @param params_ The parameters for extending the position to target leverage.
     * @param maker_ Maker of the position
     */
    function _extendPositionToLeverage(ExtendPositionToLeverageParams memory params_, address maker_) internal {
        ITradePair(params_.tradePair).extendPositionToLeverage(maker_, params_.positionId, params_.targetLeverage);

        emit PositionExtendedToLeverage(params_.tradePair, params_.positionId, params_.targetLeverage);
    }

    /* ========== LIQUIDATIONS ========== */

    /**
     * @notice Liquidates position
     * @param tradePair_ address of the trade pair
     * @param positionId_ position id
     * @param updateData_ Data to update state before the execution of the function
     */
    function liquidatePosition(address tradePair_, uint256 positionId_, UpdateData[] calldata updateData_)
        public
        onlyActiveTradePair(tradePair_)
    {
        _updateContracts(updateData_);
        ITradePair(tradePair_).liquidatePosition(msg.sender, positionId_);
        emit PositionLiquidated(tradePair_, positionId_);
    }

    /**
     * @notice Try to liquidate a position, return false if call reverts
     * @param tradePair_ address of the trade pair
     * @param positionId_ position id
     */
    function _tryLiquidatePosition(address tradePair_, uint256 positionId_, address maker_)
        internal
        onlyActiveTradePair(tradePair_)
        returns (bool)
    {
        try ITradePair(tradePair_).liquidatePosition(maker_, positionId_) {
            emit PositionLiquidated(tradePair_, positionId_);
            return true;
        } catch {
            return false;
        }
    }

    /**
     * @notice Trys to liquidates all given positions
     * @param tradePairs addresses of the trade pairs
     * @param positionIds position ids
     * @param allowRevert if true, reverts if any call reverts
     * @return didLiquidate bool[][] results of the individual liquidation calls
     * @dev Requirements
     *
     * - `tradePairs` and `positionIds` must have the same length
     */
    function batchLiquidatePositions(
        address[] calldata tradePairs,
        uint256[][] calldata positionIds,
        bool allowRevert,
        UpdateData[] calldata updateData_
    ) external returns (bool[][] memory didLiquidate) {
        require(tradePairs.length == positionIds.length, "TradeManager::batchLiquidatePositions: invalid input");
        _updateContracts(updateData_);

        didLiquidate = new bool[][](tradePairs.length);

        for (uint256 i; i < tradePairs.length; ++i) {
            didLiquidate[i] =
                _batchLiquidatePositionsOfTradePair(tradePairs[i], positionIds[i], allowRevert, msg.sender);
        }
    }

    /**
     * @notice Trys to liquidates given positions of a trade pair
     * @param tradePair address of the trade pair
     * @param positionIds position ids
     * @param allowRevert if true, reverts if any call reverts
     * @return didLiquidate bool[] results of the individual liquidation calls
     */
    function _batchLiquidatePositionsOfTradePair(
        address tradePair,
        uint256[] calldata positionIds,
        bool allowRevert,
        address maker_
    ) internal returns (bool[] memory didLiquidate) {
        didLiquidate = new bool[](positionIds.length);

        for (uint256 i; i < positionIds.length; ++i) {
            if (_tryLiquidatePosition(tradePair, positionIds[i], maker_)) {
                didLiquidate[i] = true;
            } else {
                if (allowRevert) {
                    didLiquidate[i] = false;
                } else {
                    revert("TradeManager::_batchLiquidatePositionsOfTradePair: liquidation failed");
                }
            }
        }
    }

    /* ========== VIEW FUNCTIONS ========== */

    /**
     * @notice returns the details of a position
     * @dev returns PositionDetails struct
     * @param tradePair_ address of the trade pair
     * @param positionId_ id of the position
     */
    function detailsOfPosition(address tradePair_, uint256 positionId_)
        external
        view
        returns (PositionDetails memory)
    {
        return ITradePair(tradePair_).detailsOfPosition(positionId_);
    }

    /**
     * @notice Indicates if a position is liquidatable
     * @param tradePair_ address of the trade pair
     * @param positionId_ id of the position
     */
    function positionIsLiquidatable(address tradePair_, uint256 positionId_) public view returns (bool) {
        return ITradePair(tradePair_).positionIsLiquidatable(positionId_);
    }

    /**
     * @notice Indicates if the positions are liquidatable
     * @param tradePairs_ addresses of the trade pairs
     * @param positionIds_ ids of the positions
     * @return canLiquidate array of bools indicating if the positions are liquidatable
     * @dev Requirements:
     *
     * - tradePairs_ and positionIds_ must have the same length
     */
    function canLiquidatePositions(address[] calldata tradePairs_, uint256[][] calldata positionIds_)
        external
        view
        returns (bool[][] memory canLiquidate)
    {
        require(
            tradePairs_.length == positionIds_.length,
            "TradeManager::canLiquidatePositions: TradePair and PositionId arrays must be of same length"
        );
        canLiquidate = new bool[][](tradePairs_.length);
        for (uint256 i; i < tradePairs_.length; ++i) {
            // for positionId in positionIds_
            canLiquidate[i] = _canLiquidatePositionsAtTradePair(tradePairs_[i], positionIds_[i]);
        }
    }

    /**
     * @notice Indicates if the positions are liquidatable at a given price. Used for external liquidation simulation.
     * @param tradePairs_ addresses of the trade pairs
     * @param positionIds_ ids of the positions
     * @param prices_ price to check if positions are liquidatable at
     * @return canLiquidate array of bools indicating if the positions are liquidatable
     * @dev Requirements:
     *
     * - tradePairs_ and positionIds_ must have the same length
     */
    function canLiquidatePositionsAtPrices(
        address[] calldata tradePairs_,
        uint256[][] calldata positionIds_,
        int256[] calldata prices_
    ) external view returns (bool[][] memory canLiquidate) {
        require(
            tradePairs_.length == positionIds_.length,
            "TradeManager::canLiquidatePositions: tradePairs_ and positionIds_ arrays must be of same length"
        );
        require(
            tradePairs_.length == prices_.length,
            "TradeManager::canLiquidatePositions: tradePairs_ and prices_ arrays must be of same length"
        );
        canLiquidate = new bool[][](tradePairs_.length);
        for (uint256 i; i < tradePairs_.length; ++i) {
            // for positionId in positionIds_
            canLiquidate[i] = _canLiquidatePositionsAtPriceAtTradePair(tradePairs_[i], positionIds_[i], prices_[i]);
        }
    }

    /**
     * @notice Indicates if the positions are liquidatable at a given price.
     * @param tradePair_ address of the trade pair
     * @param positionIds_ ids of the positions
     * @return canLiquidate array of bools indicating if the positions are liquidatable
     */
    function _canLiquidatePositionsAtPriceAtTradePair(
        address tradePair_,
        uint256[] calldata positionIds_,
        int256 price_
    ) internal view returns (bool[] memory) {
        bool[] memory canLiquidate = new bool[](positionIds_.length);
        for (uint256 i; i < positionIds_.length; ++i) {
            canLiquidate[i] = ITradePair(tradePair_).positionIsLiquidatableAtPrice(positionIds_[i], price_);
        }
        return canLiquidate;
    }
    /**
     * @notice Indicates if the positions are liquidatable
     * @param tradePair_ address of the trade pair
     * @param positionIds_ ids of the positions
     * @return canLiquidate array of bools indicating if the positions are liquidatable
     */

    function _canLiquidatePositionsAtTradePair(address tradePair_, uint256[] calldata positionIds_)
        internal
        view
        returns (bool[] memory)
    {
        bool[] memory canLiquidate = new bool[](positionIds_.length);
        for (uint256 i; i < positionIds_.length; ++i) {
            canLiquidate[i] = positionIsLiquidatable(tradePair_, positionIds_[i]);
        }
        return canLiquidate;
    }

    /**
     * @notice Returns the current funding fee rates of a trade pair
     * @param tradePair_ address of the trade pair
     * @return longFundingFeeRate long funding fee rate
     * @return shortFundingFeeRate short funding fee rate
     */
    function getCurrentFundingFeeRates(address tradePair_)
        external
        view
        returns (int256 longFundingFeeRate, int256 shortFundingFeeRate)
    {
        return ITradePair(tradePair_).getCurrentFundingFeeRates();
    }

    /**
     * @notice Returns the total volume limit of a trade pair. Total Volume Limit is the maximum amount of volume for
     * each trade side.
     * @param tradePair_ address of the trade pair
     * @return totalVolumeLimit
     */
    function totalVolumeLimitOfTradePair(address tradePair_) external view returns (uint256) {
        return ITradePair(tradePair_).totalVolumeLimit();
    }

    /**
     * @dev Checks if constraints_ are satisfied. If not, reverts.
     * When the transaction staid in the mempool for a long time, the price may change.
     *
     * - Price is in price range
     * - Deadline is not exceeded
     */
    function _verifyConstraints(address tradePair_, Constraints calldata constraints_, UsePrice usePrice_)
        internal
        view
    {
        // Verify Deadline
        require(constraints_.deadline > block.timestamp, "TradeManager::_verifyConstraints: Deadline passed");

        // Verify Price
        {
            int256 markPrice;

            if (usePrice_ == UsePrice.MIN) {
                (markPrice,) = ITradePair(tradePair_).getCurrentPrices();
            } else {
                (, markPrice) = ITradePair(tradePair_).getCurrentPrices();
            }

            require(
                constraints_.minPrice <= markPrice && markPrice <= constraints_.maxPrice,
                "TradeManager::_verifyConstraints: Price out of bounds"
            );
        }
    }

    /**
     * @dev Updates all updatdable contracts. Reverts if one update operation is invalid or not successfull.
     */
    function _updateContracts(UpdateData[] calldata updateData_) internal {
        for (uint256 i; i < updateData_.length; ++i) {
            require(
                controller.isUpdatable(updateData_[i].updatableContract),
                "TradeManager::_updateContracts: Contract not updatable"
            );

            IUpdatable(updateData_[i].updatableContract).update(updateData_[i].data);
        }
    }

    /* ========== MODIFIERS ========== */

    /**
     * @notice Checks if trading pair is active.
     * @param tradePair_ address of the trade pair
     */
    modifier onlyActiveTradePair(address tradePair_) {
        controller.checkTradePairActive(tradePair_);
        _;
    }
}

