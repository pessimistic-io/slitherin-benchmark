// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import { Side, PositionType } from "./LibEnums.sol";
import { PositionPrice } from "./OracleInternal.sol";
import { MasterStorage, Position, PositionState } from "./MasterStorage.sol";
import { MasterCalculators } from "./MasterCalculators.sol";
import { ICloseEvents } from "./ICloseEvents.sol";

abstract contract CloseBase is ICloseEvents {
    using MasterStorage for MasterStorage.Layout;

    function _onClosePosition(uint256 positionId, PositionPrice memory positionPrice) internal {
        MasterStorage.Layout storage s = MasterStorage.layout();
        Position storage position = s.allPositionsMap[positionId];

        uint256 price = position.side == Side.BUY ? positionPrice.bidPrice : positionPrice.askPrice;

        // Calculate the PnL of PartyA
        (int256 uPnLA, ) = MasterCalculators.calculateUPnLIsolated(
            position.positionId,
            positionPrice.bidPrice,
            positionPrice.askPrice
        );

        // Distribute the PnL accordingly
        if (position.positionType == PositionType.ISOLATED) {
            _distributePnLIsolated(position.positionId, uPnLA);
        } else {
            _distributePnLCross(position.positionId, uPnLA);
        }

        // Return parties their reserved liquidation fees
        s.marginBalances[position.partyA] += (position.liquidationFee + position.cva);
        s.marginBalances[position.partyB] += (position.liquidationFee + position.cva);

        // Emit event prior to updating the balance state
        emit ClosePosition(positionId, position.partyA, position.partyB, position.currentBalanceUnits, price);

        // Update Position
        position.state = PositionState.CLOSED;
        position.currentBalanceUnits = 0;
        position.mutableTimestamp = block.timestamp;

        // Update mappings
        if (position.positionType == PositionType.CROSS) {
            s.openPositionsCrossLength[position.partyA]--;
        }
    }

    function _updatePositionState(Position storage position, PositionState state) internal {
        position.state = state;
        position.mutableTimestamp = block.timestamp;
    }

    function _distributePnLIsolated(uint256 positionId, int256 uPnLA) private {
        MasterStorage.Layout storage s = MasterStorage.layout();
        Position memory position = s.allPositionsMap[positionId];
        require(position.positionType == PositionType.ISOLATED, "Invalid position type");

        /**
         * Winning party receives the PNL.
         * Losing party pays for the PNL using isolated margin.
         */

        if (uPnLA >= 0) {
            uint256 amount = uint256(uPnLA);
            if (amount >= position.lockedMarginB) {
                // Technically this represents a liquidation.
                s.marginBalances[position.partyA] += (position.lockedMarginA + position.lockedMarginB);
            } else {
                s.marginBalances[position.partyA] += (position.lockedMarginA + amount);
                s.marginBalances[position.partyB] += (position.lockedMarginB - amount);
            }
        } else {
            uint256 amount = uint256(-uPnLA);
            if (amount >= position.lockedMarginA) {
                // Technically this represents a liquidation.
                s.marginBalances[position.partyB] += (position.lockedMarginA + position.lockedMarginB);
            } else {
                s.marginBalances[position.partyB] += (position.lockedMarginB + amount);
                s.marginBalances[position.partyA] += (position.lockedMarginA - amount);
            }
        }
    }

    function _distributePnLCross(uint256 positionId, int256 uPnLA) private {
        MasterStorage.Layout storage s = MasterStorage.layout();
        Position memory position = s.allPositionsMap[positionId];
        require(position.positionType == PositionType.CROSS, "Invalid position type");

        /**
         * Winning party receives the PNL.
         * Losing party pays for the PNL using his globally lockedMargin (Cross).
         */
        address partyA = position.partyA;
        address partyB = position.partyB;

        if (uPnLA >= 0) {
            /**
             * PartyA will NOT receive his lockedMargin back,
             * he'll have to withdraw it manually. This has to do with the
             * risk of liquidation + the fact that his initially lockedMargin
             * could be greater than what he currently has locked.
             */
            uint256 amount = uint256(uPnLA);
            if (amount >= position.lockedMarginB) {
                // Technically this represents a liquidation.
                s.marginBalances[position.partyA] += position.lockedMarginB;
                // We don't have to reset the lockedMargin of PartyB because he's Isolated.
            } else {
                s.marginBalances[position.partyA] += amount;
                s.marginBalances[position.partyB] += (position.lockedMarginB - amount);
            }
        } else {
            uint256 amount = uint256(-uPnLA);
            // PartyB is Isolated by nature.
            if (amount >= s.crossLockedMargin[partyA]) {
                // Technically this represents a liquidation.
                s.marginBalances[partyB] += (s.crossLockedMargin[partyA] + position.lockedMarginB);
                s.crossLockedMargin[partyA] = 0;
            } else {
                s.marginBalances[partyB] += (position.lockedMarginB + amount);
                s.crossLockedMargin[partyA] -= amount;
            }
        }
    }
}

