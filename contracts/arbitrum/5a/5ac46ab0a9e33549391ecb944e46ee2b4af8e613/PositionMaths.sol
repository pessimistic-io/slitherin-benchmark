// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.17;

import "./Math.sol";

import "./Constants.sol";

interface ITradePair_Multiplier {
    function collateralToPriceMultiplier() external view returns (uint256);
}

/* ========== STRUCTS ========== */
/**
 * @notice Struct to store details of a position
 * @custom:member margin the margin of the position
 * @custom:member volume the volume of the position
 * @custom:member assetAmount the underlying amount of assets. Normalized to  ASSET_DECIMALS
 * @custom:member pastBorrowFeeIntegral the integral of borrow fee at the moment of opening or last fee update
 * @custom:member lastBorrowFeeAmount the last borrow fee amount at the moment of last fee update
 * @custom:member pastFundingFeeIntegral the integral of funding fee at the moment of opening or last fee update
 * @custom:member lastFundingFeeAmount the last funding fee amount at the moment of last fee update
 * @custom:member collectedFundingFeeAmount the total collected funding fee amount, to add up the total funding fee amount
 * @custom:member lastFeeCalculationAt moment of the last fee update
 * @custom:member openedAt moment of the position opening
 * @custom:member isShort bool if the position is short
 * @custom:member owner the owner of the position
 * @custom:member lastAlterationBlock the last block where the position was altered or opened
 */
struct Position {
    uint256 margin;
    uint256 volume;
    uint256 assetAmount;
    int256 pastBorrowFeeIntegral;
    int256 lastBorrowFeeAmount;
    int256 collectedBorrowFeeAmount;
    int256 pastFundingFeeIntegral;
    int256 lastFundingFeeAmount;
    int256 collectedFundingFeeAmount;
    uint48 lastFeeCalculationAt;
    uint48 openedAt;
    bool isShort;
    address owner;
    uint40 lastAlterationBlock;
}

/**
 * @title Position Maths
 * @notice Provides financial maths for leveraged positions.
 */
library PositionMaths {
    /**
     * External Functions
     */

    /**
     * @notice Price at entry level
     * @return price int
     */
    function entryPrice(Position storage self) public view returns (int256) {
        return self._entryPrice();
    }

    function _entryPrice(Position storage self) internal view returns (int256) {
        return int256(self.volume * collateralToPriceMultiplier() * ASSET_MULTIPLIER / self.assetAmount);
    }

    /**
     * @notice Leverage at entry level
     * @return leverage uint
     */
    function entryLeverage(Position storage self) public view returns (uint256) {
        return self._entryLeverage();
    }

    function _entryLeverage(Position storage self) internal view returns (uint256) {
        return self.volume * LEVERAGE_MULTIPLIER / self.margin;
    }

    /**
     * @notice Last net leverage is calculated with the last net margin, which is entry margin minus last total fees. Margin of zero means position is liquidatable.
     * @return net leverage uint. When margin is less than zero, leverage is max uint256
     * @dev this value is only valid when the position got updated at the same block
     */
    function lastNetLeverage(Position storage self) public view returns (uint256) {
        return self._lastNetLeverage();
    }

    function _lastNetLeverage(Position storage self) internal view returns (uint256) {
        uint256 lastNetMargin_ = self._lastNetMargin();
        if (lastNetMargin_ == 0) {
            return type(uint256).max;
        }
        return self.volume * LEVERAGE_MULTIPLIER / lastNetMargin_;
    }

    /**
     * @notice Current Net Margin, which is entry margin minus current total fees. Margin of zero means position is liquidatable.
     * @return net margin int
     */
    function currentNetMargin(Position storage self, int256 currentBorrowFeeIntegral, int256 currentFundingFeeIntegral)
        public
        view
        returns (uint256)
    {
        return self._currentNetMargin(currentBorrowFeeIntegral, currentFundingFeeIntegral);
    }

    function _currentNetMargin(Position storage self, int256 currentBorrowFeeIntegral, int256 currentFundingFeeIntegral)
        internal
        view
        returns (uint256)
    {
        int256 actualCurrentMargin =
            int256(self.margin) - self._currentTotalFeeAmount(currentBorrowFeeIntegral, currentFundingFeeIntegral);
        return actualCurrentMargin > 0 ? uint256(actualCurrentMargin) : 0;
    }

    /**
     * @notice Returns the last net margin, calculated at the moment of last fee update
     * @return last net margin uint. Can be zero.
     * @dev this value is only valid when the position got updated at the same block
     * It is a convenience function because the caller does not need to provice fee integrals
     */
    function lastNetMargin(Position storage self) internal view returns (uint256) {
        return self._lastNetMargin();
    }

    function _lastNetMargin(Position storage self) internal view returns (uint256) {
        int256 _lastMargin = int256(self.margin) - self.lastBorrowFeeAmount - self.lastFundingFeeAmount;
        return _lastMargin > 0 ? uint256(_lastMargin) : 0;
    }

    /**
     * @notice Current Net Leverage, which is entry volume divided by current net margin
     * @return current net leverage
     */
    function currentNetLeverage(
        Position storage self,
        int256 currentBorrowFeeIntegral,
        int256 currentFundingFeeIntegral
    ) public view returns (uint256) {
        return self._currentNetLeverage(currentBorrowFeeIntegral, currentFundingFeeIntegral);
    }

    function _currentNetLeverage(
        Position storage self,
        int256 currentBorrowFeeIntegral,
        int256 currentFundingFeeIntegral
    ) internal view returns (uint256) {
        uint256 currentNetMargin_ = self._currentNetMargin(currentBorrowFeeIntegral, currentFundingFeeIntegral);
        if (currentNetMargin_ == 0) {
            return type(uint256).max;
        }
        return self.volume * LEVERAGE_MULTIPLIER / currentNetMargin_;
    }

    /**
     * @notice Liquidation price takes into account fee-reduced collateral and absolute maintenance margin
     * @return liquidationPrice int
     */
    function liquidationPrice(
        Position storage self,
        int256 currentBorrowFeeIntegral,
        int256 currentFundingFeeIntegral,
        uint256 maintenanceMargin
    ) public view returns (int256) {
        return self._liquidationPrice(currentBorrowFeeIntegral, currentFundingFeeIntegral, maintenanceMargin);
    }

    function _liquidationPrice(
        Position storage self,
        int256 currentBorrowFeeIntegral,
        int256 currentFundingFeeIntegral,
        uint256 maintenanceMargin
    ) internal view returns (int256) {
        // Reduce current margin by liquidator reward
        int256 liquidatableMargin = int256(self._currentNetMargin(currentBorrowFeeIntegral, currentFundingFeeIntegral))
            - int256(maintenanceMargin);

        // If margin is zero, position is liquidatable by fee reduction alone.
        // Return entry price
        if (liquidatableMargin <= 0) {
            return self._entryPrice();
        }

        // Return entryPrice +/- entryPrice / leverage
        // Where leverage = volume / liquidatableMargin
        return self._entryPrice()
            - self._entryPrice() * int256(LEVERAGE_MULTIPLIER) * self._shortMultiplier() * liquidatableMargin
                / int256(self.volume * LEVERAGE_MULTIPLIER);
    }

    function _shortMultiplier(Position storage self) internal view returns (int256) {
        if (self.isShort) {
            return int256(-1);
        } else {
            return int256(1);
        }
    }

    /**
     * @notice Current Volume is the current mark price times the asset amount (this is not the current value)
     * @param currentPrice int current mark price
     * @return currentVolume uint
     */
    function currentVolume(Position storage self, int256 currentPrice) public view returns (uint256) {
        return self._currentVolume(currentPrice);
    }

    function _currentVolume(Position storage self, int256 currentPrice) internal view returns (uint256) {
        return self.assetAmount * uint256(currentPrice) / ASSET_MULTIPLIER / collateralToPriceMultiplier();
    }

    /**
     * @notice Current Profit and Losses (without fees)
     * @param currentPrice int current mark price
     * @return currentPnL int
     */
    function currentPnL(Position storage self, int256 currentPrice) public view returns (int256) {
        return self._currentPnL(currentPrice);
    }

    function _currentPnL(Position storage self, int256 currentPrice) internal view returns (int256) {
        return (int256(self._currentVolume(currentPrice)) - int256(self.volume)) * self._shortMultiplier();
    }

    /**
     * @notice Current Value is the derived value that takes into account entry volume and PNL
     * @dev This value is shown on the UI. It normalized the differences of LONG/SHORT into a single value
     * @param currentPrice int current mark price
     * @return currentValue int
     */
    function currentValue(Position storage self, int256 currentPrice) public view returns (int256) {
        return self._currentValue(currentPrice);
    }

    function _currentValue(Position storage self, int256 currentPrice) internal view returns (int256) {
        return int256(self.volume) + self._currentPnL(currentPrice);
    }

    /**
     * @notice Current Equity (without fees)
     * @param currentPrice int current mark price
     * @return currentEquity int
     */
    function currentEquity(Position storage self, int256 currentPrice) public view returns (int256) {
        return self._currentEquity(currentPrice);
    }

    function _currentEquity(Position storage self, int256 currentPrice) internal view returns (int256) {
        return self._currentPnL(currentPrice) + int256(self.margin);
    }

    function currentTotalFeeAmount(
        Position storage self,
        int256 currentBorrowFeeIntegral,
        int256 currentFundingFeeIntegral
    ) public view returns (int256) {
        return self._currentTotalFeeAmount(currentBorrowFeeIntegral, currentFundingFeeIntegral);
    }

    function _currentTotalFeeAmount(
        Position storage self,
        int256 currentBorrowFeeIntegral,
        int256 currentFundingFeeIntegral
    ) internal view returns (int256) {
        return self._currentBorrowFeeAmount(currentBorrowFeeIntegral)
            + self._currentFundingFeeAmount(currentFundingFeeIntegral);
    }

    /**
     * @notice Current Amount of Funding Fee, accumulated over time
     * @param currentFundingFeeIntegral uint current funding fee integral
     * @return currentFundingFeeAmount int
     */
    function currentFundingFeeAmount(Position storage self, int256 currentFundingFeeIntegral)
        public
        view
        returns (int256)
    {
        return self._currentFundingFeeAmount(currentFundingFeeIntegral);
    }

    function _currentFundingFeeAmount(Position storage self, int256 currentFundingFeeIntegral)
        internal
        view
        returns (int256)
    {
        int256 elapsedFundingFeeAmount =
            (currentFundingFeeIntegral - self.pastFundingFeeIntegral) * int256(self.volume) / FEE_MULTIPLIER;
        return self.lastFundingFeeAmount + elapsedFundingFeeAmount;
    }

    /**
     * @notice Current amount of borrow fee, accumulated over time
     * @param currentBorrowFeeIntegral uint current fee integral
     * @return currentBorrowFeeAmount int
     */
    function currentBorrowFeeAmount(Position storage self, int256 currentBorrowFeeIntegral)
        public
        view
        returns (int256)
    {
        return self._currentBorrowFeeAmount(currentBorrowFeeIntegral);
    }

    function _currentBorrowFeeAmount(Position storage self, int256 currentBorrowFeeIntegral)
        internal
        view
        returns (int256)
    {
        return self.lastBorrowFeeAmount
            + (currentBorrowFeeIntegral - self.pastBorrowFeeIntegral) * int256(self.volume) / FEE_MULTIPLIER;
    }

    /**
     * @notice Current Net PnL, including fees
     * @param currentPrice int current mark price
     * @param currentBorrowFeeIntegral uint current fee integral
     * @param currentFundingFeeIntegral uint current funding fee integral
     * @return currentNetPnL int
     */
    function currentNetPnL(
        Position storage self,
        int256 currentPrice,
        int256 currentBorrowFeeIntegral,
        int256 currentFundingFeeIntegral
    ) public view returns (int256) {
        return self._currentNetPnL(currentPrice, currentBorrowFeeIntegral, currentFundingFeeIntegral);
    }

    function _currentNetPnL(
        Position storage self,
        int256 currentPrice,
        int256 currentBorrowFeeIntegral,
        int256 currentFundingFeeIntegral
    ) internal view returns (int256) {
        return self._currentPnL(currentPrice)
            - int256(self._currentTotalFeeAmount(currentBorrowFeeIntegral, currentFundingFeeIntegral));
    }

    /**
     * @notice Current Net Equity, including fees
     * @param currentPrice int current mark price
     * @param currentBorrowFeeIntegral uint current fee integral
     * @param currentFundingFeeIntegral uint current funding fee integral
     * @return currentNetEquity int
     */
    function currentNetEquity(
        Position storage self,
        int256 currentPrice,
        int256 currentBorrowFeeIntegral,
        int256 currentFundingFeeIntegral
    ) public view returns (int256) {
        return self._currentNetEquity(currentPrice, currentBorrowFeeIntegral, currentFundingFeeIntegral);
    }

    function _currentNetEquity(
        Position storage self,
        int256 currentPrice,
        int256 currentBorrowFeeIntegral,
        int256 currentFundingFeeIntegral
    ) internal view returns (int256) {
        return
            self._currentNetPnL(currentPrice, currentBorrowFeeIntegral, currentFundingFeeIntegral) + int256(self.margin);
    }

    /**
     * @notice Determines if the position can be liquidated
     * @param currentPrice int current mark price
     * @param currentBorrowFeeIntegral uint current fee integral
     * @param currentFundingFeeIntegral uint current funding fee integral
     * @param absoluteMaintenanceMargin absolute amount of maintenance margin.
     * @return isLiquidatable bool
     * @dev A position is liquidatable, when either the margin or the current equity
     * falls under or equals the absolute maintenance margin
     */
    function isLiquidatable(
        Position storage self,
        int256 currentPrice,
        int256 currentBorrowFeeIntegral,
        int256 currentFundingFeeIntegral,
        uint256 absoluteMaintenanceMargin
    ) public view returns (bool) {
        return self._isLiquidatable(
            currentPrice, currentBorrowFeeIntegral, currentFundingFeeIntegral, absoluteMaintenanceMargin
        );
    }

    function _isLiquidatable(
        Position storage self,
        int256 currentPrice,
        int256 currentBorrowFeeIntegral,
        int256 currentFundingFeeIntegral,
        uint256 absoluteMaintenanceMargin
    ) internal view returns (bool) {
        // If margin does not cover fees, position is liquidatable.
        if (
            int256(self.margin)
                <= int256(absoluteMaintenanceMargin)
                    + int256(self._currentTotalFeeAmount(currentBorrowFeeIntegral, currentFundingFeeIntegral))
        ) {
            return true;
        }
        // Otherwise, a position is liquidatable if equity is below the absolute maintenance margin.
        return self._currentNetEquity(currentPrice, currentBorrowFeeIntegral, currentFundingFeeIntegral)
            <= int256(absoluteMaintenanceMargin);
    }

    /* ========== POSITION ALTERATIONS ========== */

    /**
     * @notice Partially closes a position
     * @param currentPrice int current mark price
     * @param closeProportion the share of the position that should be closed
     */
    function partiallyClose(Position storage self, int256 currentPrice, uint256 closeProportion)
        public
        returns (int256)
    {
        return self._partiallyClose(currentPrice, closeProportion);
    }

    /**
     * @dev Partially closing works as follows:
     *
     * 1. Sell a share of the position, and use the proceeds to either:
     * 2.a) Get a payout and by this, leave the leverage as it is
     * 2.b) "Buy" new margin and by this decrease the leverage
     * 2.c) a mixture of 2.a) and 2.b)
     */
    function _partiallyClose(Position storage self, int256 currentPrice, uint256 closeProportion)
        internal
        returns (int256)
    {
        require(
            closeProportion < PERCENTAGE_MULTIPLIER,
            "PositionMaths::_partiallyClose: cannot partially close full position"
        );

        Position memory delta;
        // Close a proportional share of the position
        delta.margin = self._lastNetMargin() * closeProportion / PERCENTAGE_MULTIPLIER;
        delta.volume = self.volume * closeProportion / PERCENTAGE_MULTIPLIER;
        delta.assetAmount = self.assetAmount * closeProportion / PERCENTAGE_MULTIPLIER;

        // The realized PnL is the change in volume minus the price of the changes in size at LONG
        // And the inverse of that at SHORT
        // @dev At a long position, the delta of size is sold to give back the volume
        // @dev At a short position, the volume delta is used, to "buy" the change of size (and give it back)
        int256 priceOfSizeDelta =
            currentPrice * int256(delta.assetAmount) / int256(collateralToPriceMultiplier()) / int256(ASSET_MULTIPLIER);
        int256 realizedPnL = (priceOfSizeDelta - int256(delta.volume)) * self._shortMultiplier();

        int256 payout = int256(delta.margin) + realizedPnL;

        // change storage values
        self.margin -= self.margin * closeProportion / PERCENTAGE_MULTIPLIER;
        self.volume -= delta.volume;
        self.assetAmount -= delta.assetAmount;

        // Update borrow fee amounts
        self.collectedBorrowFeeAmount +=
            self.lastBorrowFeeAmount * int256(closeProportion) / int256(PERCENTAGE_MULTIPLIER);
        self.lastBorrowFeeAmount -= self.lastBorrowFeeAmount * int256(closeProportion) / int256(PERCENTAGE_MULTIPLIER);

        // Update funding fee amounts
        self.collectedFundingFeeAmount +=
            self.lastFundingFeeAmount * int256(closeProportion) / int256(PERCENTAGE_MULTIPLIER);
        self.lastFundingFeeAmount -= self.lastFundingFeeAmount * int256(closeProportion) / int256(PERCENTAGE_MULTIPLIER);

        // Return payout for further calculations
        return payout;
    }

    /**
     * @notice Adds margin to a position
     * @param addedMargin the margin that gets added to the position
     */
    function addMargin(Position storage self, uint256 addedMargin) public {
        self._addMargin(addedMargin);
    }

    function _addMargin(Position storage self, uint256 addedMargin) internal {
        self.margin += addedMargin;
    }

    /**
     * @notice Removes margin from a position
     * @dev The remaining equity has to stay positive
     * @param removedMargin the margin to remove
     */
    function removeMargin(Position storage self, uint256 removedMargin) public {
        self._removeMargin(removedMargin);
    }

    function _removeMargin(Position storage self, uint256 removedMargin) internal {
        require(self.margin > removedMargin, "PositionMaths::_removeMargin: cannot remove more margin than available");
        self.margin -= removedMargin;
    }

    /**
     * @notice Extends position with margin and loan.
     * @param addedMargin Margin added to position.
     * @param addedAssetAmount Asset amount added to position.
     * @param addedVolume Loan added to position.
     */
    function extend(Position storage self, uint256 addedMargin, uint256 addedAssetAmount, uint256 addedVolume) public {
        self._extend(addedMargin, addedAssetAmount, addedVolume);
    }

    function _extend(Position storage self, uint256 addedMargin, uint256 addedAssetAmount, uint256 addedVolume)
        internal
    {
        self.margin += addedMargin;
        self.assetAmount += addedAssetAmount;
        self.volume += addedVolume;
    }

    /**
     * @notice Extends position with loan to target leverage.
     * @param currentPrice current asset price
     * @param targetLeverage target leverage
     */
    function extendToLeverage(Position storage self, int256 currentPrice, uint256 targetLeverage) public {
        self._extendToLeverage(currentPrice, targetLeverage);
    }

    function _extendToLeverage(Position storage self, int256 currentPrice, uint256 targetLeverage) internal {
        require(
            targetLeverage > self._lastNetLeverage(),
            "PositionMaths::_extendToLeverage: target leverage must be larger than current leverage"
        );

        // calculate changes
        Position memory delta;
        delta.volume = targetLeverage * self._lastNetMargin() / LEVERAGE_MULTIPLIER - self.volume;
        delta.assetAmount = delta.volume * collateralToPriceMultiplier() * ASSET_MULTIPLIER / uint256(currentPrice);

        // store changes
        self.assetAmount += delta.assetAmount;
        self.volume += delta.volume;
    }

    /**
     * @notice Returns if the position exists / is open
     */
    function exists(Position storage self) public view returns (bool) {
        return self._exists();
    }

    function _exists(Position storage self) internal view returns (bool) {
        return self.margin > 0;
    }

    /**
     * @notice Adds all elapsed fees to the fee amounts. After this, the position can be altered.
     */
    function updateFees(Position storage self, int256 currentBorrowFeeIntegral, int256 currentFundingFeeIntegral)
        public
    {
        self._updateFees(currentBorrowFeeIntegral, currentFundingFeeIntegral);
    }

    /**
     * Internal Functions (that are only called internally and not mirror a public function)
     */

    function _updateFees(Position storage self, int256 currentBorrowFeeIntegral, int256 currentFundingFeeIntegral)
        internal
    {
        int256 elapsedBorrowFeeAmount =
            (currentBorrowFeeIntegral - self.pastBorrowFeeIntegral) * int256(self.volume) / FEE_MULTIPLIER;
        int256 elapsedFundingFeeAmount =
            (currentFundingFeeIntegral - self.pastFundingFeeIntegral) * int256(self.volume) / FEE_MULTIPLIER;

        self.lastBorrowFeeAmount += elapsedBorrowFeeAmount;
        self.lastFundingFeeAmount += elapsedFundingFeeAmount;
        self.pastBorrowFeeIntegral = currentBorrowFeeIntegral;
        self.pastFundingFeeIntegral = currentFundingFeeIntegral;
        self.lastFeeCalculationAt = uint48(block.timestamp);
    }

    /**
     * @notice Returns the multiplier from TradePair, as PositionMaths is decimal agnostic
     */
    function collateralToPriceMultiplier() private view returns (uint256) {
        return ITradePair_Multiplier(address(this)).collateralToPriceMultiplier();
    }
}

using PositionMaths for Position;

