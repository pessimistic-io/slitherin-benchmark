// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.16;

import { AppStorage, LibAppStorage, RequestForQuote, Position, Fill } from "./LibAppStorage.sol";
import { LibDiamond } from "./LibDiamond.sol";
import { LibMarkets } from "./LibMarkets.sol";
import { PositionPrice } from "./LibOracle.sol";
import { Decimal } from "./LibDecimal.sol";
import { C } from "./C.sol";
import "./LibEnums.sol";

library LibMaster {
    using Decimal for Decimal.D256;

    // --------------------------------//
    //---- INTERNAL WRITE FUNCTIONS ---//
    // --------------------------------//

    function onRequestForQuote(
        address partyA,
        address partyB,
        uint256 marketId,
        PositionType positionType,
        OrderType orderType,
        HedgerMode hedgerMode,
        Side side,
        uint256 usdAmountToSpend,
        uint16 leverage,
        uint256 minExpectedUnits,
        uint256 maxExpectedUnits
    ) internal returns (RequestForQuote memory rfq) {
        AppStorage storage s = LibAppStorage.diamondStorage();

        require(LibMarkets.isValidMarketId(marketId), "Invalid market");

        uint256 notionalUsd = usdAmountToSpend * leverage;
        uint256 protocolFee = calculateProtocolFeeAmount(notionalUsd);
        uint256 liquidationFee = calculateLiquidationFeeAmount(notionalUsd);
        uint256 cva = calculateCVAAmount(notionalUsd);
        uint256 amount = usdAmountToSpend + protocolFee + liquidationFee + cva;

        require(amount <= s.ma._marginBalances[partyA], "Insufficient margin balance");
        s.ma._marginBalances[partyA] -= amount;
        s.ma._lockedMarginReserved[partyA] += amount;

        // Create the RFQ
        uint256 currentRfqId = s.ma._requestForQuotesLength + 1;
        rfq = RequestForQuote({
            rfqId: currentRfqId,
            state: RequestForQuoteState.ORPHAN,
            positionType: positionType,
            orderType: orderType,
            partyA: partyA,
            partyB: partyB,
            hedgerMode: hedgerMode,
            marketId: marketId,
            side: side,
            notionalUsd: notionalUsd,
            leverageUsed: leverage,
            lockedMargin: usdAmountToSpend,
            protocolFee: protocolFee,
            liquidationFee: liquidationFee,
            cva: cva,
            minExpectedUnits: minExpectedUnits,
            maxExpectedUnits: maxExpectedUnits,
            creationTimestamp: block.timestamp,
            mutableTimestamp: block.timestamp
        });

        s.ma._requestForQuotesMap[currentRfqId] = rfq;
        s.ma._requestForQuotesLength++;
    }

    function onFillOpenMarket(
        address partyB,
        uint256 rfqId,
        uint256 filledAmountUnits,
        uint256 avgPriceUsd
    ) internal returns (Position memory position) {
        AppStorage storage s = LibAppStorage.diamondStorage();
        RequestForQuote storage rfq = s.ma._requestForQuotesMap[rfqId];

        require(
            rfq.state == RequestForQuoteState.ORPHAN || rfq.state == RequestForQuoteState.CANCELATION_REQUESTED,
            "Invalid RFQ state"
        );
        require(rfq.minExpectedUnits <= filledAmountUnits, "Invalid min filled amount");
        require(rfq.maxExpectedUnits >= filledAmountUnits, "Invalid max filled amount");

        // Update the RFQ
        rfq.state = RequestForQuoteState.ACCEPTED;
        rfq.mutableTimestamp = block.timestamp;

        // Create the Position
        uint256 currentPositionId = s.ma._allPositionsLength + 1;
        position = Position({
            positionId: currentPositionId,
            state: PositionState.OPEN,
            positionType: rfq.positionType,
            marketId: rfq.marketId,
            partyA: rfq.partyA,
            partyB: rfq.partyB,
            leverageUsed: rfq.leverageUsed,
            side: rfq.side,
            lockedMargin: rfq.lockedMargin,
            protocolFeePaid: rfq.protocolFee,
            liquidationFee: rfq.liquidationFee,
            cva: rfq.cva,
            currentBalanceUnits: filledAmountUnits,
            initialNotionalUsd: rfq.notionalUsd,
            creationTimestamp: block.timestamp,
            mutableTimestamp: block.timestamp
        });

        // Create the first Fill
        createFill(currentPositionId, rfq.side, filledAmountUnits, avgPriceUsd);

        // Update global mappings
        s.ma._allPositionsMap[currentPositionId] = position;
        s.ma._allPositionsLength++;

        // Transfer partyA's collateral
        uint256 deductableMarginA = rfq.lockedMargin + rfq.protocolFee + rfq.liquidationFee + rfq.cva;
        s.ma._lockedMarginReserved[rfq.partyA] -= deductableMarginA;

        // Transfer partyB's collateral
        uint256 deductableMarginB = rfq.lockedMargin + rfq.liquidationFee + rfq.cva; // hedger doesn't pay protocolFee
        require(deductableMarginB <= s.ma._marginBalances[partyB], "Insufficient margin balance");
        s.ma._marginBalances[partyB] -= deductableMarginB;

        // Distribute the fee paid by partyA
        s.ma._accountBalances[LibDiamond.contractOwner()] += rfq.protocolFee;

        if (rfq.positionType == PositionType.ISOLATED) {
            s.ma._openPositionsIsolatedLength[rfq.partyA]++;
            s.ma._openPositionsIsolatedLength[partyB]++;
        } else {
            s.ma._openPositionsCrossLength[rfq.partyA]++;
            s.ma._openPositionsIsolatedLength[partyB]++;

            // Lock margins
            s.ma._lockedMargin[rfq.partyA] += rfq.lockedMargin;
            s.ma._lockedMargin[partyB] += rfq.lockedMargin;
        }
    }

    function onFillCloseMarket(uint256 positionId, PositionPrice memory positionPrice) internal {
        AppStorage storage s = LibAppStorage.diamondStorage();
        Position storage position = s.ma._allPositionsMap[positionId];

        uint256 price = position.side == Side.BUY ? positionPrice.bidPrice : positionPrice.askPrice;

        // Add the Fill
        createFill(positionId, position.side == Side.BUY ? Side.SELL : Side.BUY, position.currentBalanceUnits, price);

        // Calculate the PnL of PartyA
        (int256 pnlA, , ) = _calculateUPnLIsolated(
            position.side,
            position.currentBalanceUnits,
            position.initialNotionalUsd,
            positionPrice.bidPrice,
            positionPrice.askPrice
        );

        // Distribute the PnL accordingly
        if (position.positionType == PositionType.ISOLATED) {
            distributePnLIsolated(position.positionId, pnlA);
        } else {
            distributePnLCross(position.positionId, pnlA);
        }

        // Return parties their reserved liquidation fees
        s.ma._marginBalances[position.partyA] += (position.liquidationFee + position.cva);
        s.ma._marginBalances[position.partyB] += (position.liquidationFee + position.cva);

        // Update Position
        position.state = PositionState.CLOSED;
        position.currentBalanceUnits = 0;
        position.mutableTimestamp = block.timestamp;

        // Update mappings
        if (position.positionType == PositionType.ISOLATED) {
            s.ma._openPositionsIsolatedLength[position.partyA]--;
            s.ma._openPositionsIsolatedLength[position.partyB]--;
        } else {
            s.ma._openPositionsCrossLength[position.partyA]--;
            s.ma._openPositionsIsolatedLength[position.partyB]--;
        }
    }

    function distributePnLIsolated(uint256 positionId, int256 pnlA) internal {
        AppStorage storage s = LibAppStorage.diamondStorage();
        Position memory position = s.ma._allPositionsMap[positionId];
        require(position.positionType == PositionType.ISOLATED, "Invalid position type");

        /**
         * Winning party receives the PNL.
         * Losing party pays for the PNL using the margin that was locked inside the position.
         */

        if (pnlA >= 0) {
            uint256 amount = uint256(pnlA);
            if (amount > position.lockedMargin) {
                s.ma._marginBalances[position.partyA] += position.lockedMargin * 2;
            } else {
                s.ma._marginBalances[position.partyA] += (position.lockedMargin + amount);
                s.ma._marginBalances[position.partyB] += (position.lockedMargin - amount);
            }
        } else {
            uint256 amount = uint256(-pnlA);
            if (amount > position.lockedMargin) {
                s.ma._marginBalances[position.partyB] += position.lockedMargin * 2;
            } else {
                s.ma._marginBalances[position.partyB] += (position.lockedMargin + amount);
                s.ma._marginBalances[position.partyA] += (position.lockedMargin - amount);
            }
        }
    }

    function distributePnLCross(uint256 positionId, int256 pnlA) internal {
        AppStorage storage s = LibAppStorage.diamondStorage();
        Position memory position = s.ma._allPositionsMap[positionId];
        require(position.positionType == PositionType.CROSS, "Invalid position type");

        /**
         * Winning party receives the PNL.
         * If partyA is the losing party: pays for the PNL using his lockedMargin.
         * If partyB is the losing party: pays for the PNL using his margin locked inside the position (he's isolated).
         */
        address partyA = position.partyA;
        address partyB = position.partyB;

        if (pnlA >= 0) {
            /**
             * PartyA will NOT receive his lockedMargin back,
             * he'll have to withdraw it manually. This has to do with the
             * risk of liquidation + the fact that his initially lockedMargin
             * could be greater than what he currently has locked.
             */
            uint256 amount = uint256(pnlA);
            if (amount > position.lockedMargin) {
                s.ma._marginBalances[position.partyA] += position.lockedMargin;
            } else {
                s.ma._marginBalances[position.partyA] += amount;
                s.ma._marginBalances[position.partyB] += (position.lockedMargin - amount);
            }
        } else {
            uint256 amount = uint256(-pnlA);
            if (s.ma._lockedMargin[partyA] < amount) {
                s.ma._marginBalances[partyB] += (s.ma._lockedMargin[partyA] + position.lockedMargin);
                s.ma._lockedMargin[partyA] = 0;
            } else {
                s.ma._marginBalances[partyB] += (amount + position.lockedMargin);
                s.ma._lockedMargin[partyA] -= amount;
            }
        }
    }

    function createFill(
        uint256 positionId,
        Side side,
        uint256 amount,
        uint256 price
    ) internal {
        AppStorage storage s = LibAppStorage.diamondStorage();
        uint256 fillId = s.ma._positionFills[positionId].length;
        Fill memory fill = Fill(fillId, positionId, side, amount, price, block.timestamp);
        s.ma._positionFills[positionId].push(fill);
    }

    // --------------------------------//
    //---- INTERNAL VIEW FUNCTIONS ----//
    // --------------------------------//

    /**
     * @notice Returns the UPnL for a specific position.
     * @dev This is a naive function, inputs can not be trusted. Use cautiously.
     */
    function calculateUPnLIsolated(
        uint256 positionId,
        uint256 bidPrice,
        uint256 askPrice
    ) internal view returns (int256 uPnLA, int256 uPnLB) {
        AppStorage storage s = LibAppStorage.diamondStorage();
        Position memory position = s.ma._allPositionsMap[positionId];

        (uPnLA, uPnLB, ) = _calculateUPnLIsolated(
            position.side,
            position.currentBalanceUnits,
            position.initialNotionalUsd,
            bidPrice,
            askPrice
        );
    }

    /**
     * @notice Returns the UPnL of a party across all his open positions.
     * @dev This is a naive function, inputs can NOT be trusted. Use cautiously.
     *      Use Muon to verify inputs to prevent expensive computational costs.
     * @dev positionPrices can have an incorrect length.
     * @dev positionPrices can have an arbitrary order.
     * @dev positionPrices can contain forged duplicates.
     */
    function calculateUPnLCross(PositionPrice[] memory positionPrices, address party)
        internal
        view
        returns (int256 uPnLCross, int256 notionalCross)
    {
        (uPnLCross, notionalCross) = _calculateUPnLCross(positionPrices, party);
    }

    function calculateProtocolFeeAmount(uint256 notionalUsd) internal view returns (uint256) {
        return Decimal.from(notionalUsd).mul(C.getProtocolFee()).asUint256();
    }

    function calculateLiquidationFeeAmount(uint256 notionalUsd) internal view returns (uint256) {
        return Decimal.from(notionalUsd).mul(C.getLiquidationFee()).asUint256();
    }

    function calculateCVAAmount(uint256 notionalSize) internal view returns (uint256) {
        return Decimal.from(notionalSize).mul(C.getCVA()).asUint256();
    }

    function calculateCrossMarginHealth(uint256 lockedMargin, int256 uPnLCross)
        internal
        pure
        returns (Decimal.D256 memory ratio)
    {
        if (lockedMargin == 0) {
            return Decimal.ratio(1, 1);
        }

        if (uPnLCross >= 0) {
            return Decimal.ratio(lockedMargin + uint256(uPnLCross), lockedMargin);
        }

        uint256 pnl = uint256(-uPnLCross);
        if (pnl >= lockedMargin) {
            return Decimal.zero();
        }

        ratio = Decimal.ratio(lockedMargin - pnl, lockedMargin);
    }

    function positionShouldBeLiquidatedIsolated(
        uint256 positionId,
        uint256 bidPrice,
        uint256 askPrice
    )
        internal
        view
        returns (
            bool shouldBeLiquidated,
            int256 pnlA,
            int256 pnlB
        )
    {
        AppStorage storage s = LibAppStorage.diamondStorage();
        Position memory position = s.ma._allPositionsMap[positionId];
        require(position.positionType == PositionType.ISOLATED, "Position is not isolated");
        (pnlA, pnlB) = calculateUPnLIsolated(positionId, bidPrice, askPrice);
        shouldBeLiquidated = pnlA <= 0
            ? uint256(pnlB) >= position.lockedMargin
            : uint256(pnlA) >= position.lockedMargin;
    }

    function partyShouldBeLiquidatedCross(address party, int256 uPnLCross) internal view returns (bool) {
        AppStorage storage s = LibAppStorage.diamondStorage();
        return calculateCrossMarginHealth(s.ma._lockedMargin[party], uPnLCross).isZero();
    }

    // --------------------------------//
    //----- PRIVATE VIEW FUNCTIONS ----//
    // --------------------------------//

    /**
     * @notice Returns the UPnL for a specific position.
     * @dev This is a naive function, inputs can not be trusted. Use cautiously.
     */
    function _calculateUPnLIsolated(
        Side side,
        uint256 currentBalanceUnits,
        uint256 initialNotionalUsd,
        uint256 bidPrice,
        uint256 askPrice
    )
        private
        pure
        returns (
            int256 uPnLA,
            int256 uPnLB,
            int256 notionalIsolated
        )
    {
        if (currentBalanceUnits == 0) return (0, 0, 0);

        uint256 precision = C.getPrecision();

        if (side == Side.BUY) {
            require(bidPrice != 0, "Oracle bidPrice is invalid");
            notionalIsolated = int256((currentBalanceUnits * bidPrice) / precision);
            uPnLA = notionalIsolated - int256(initialNotionalUsd);
        } else {
            require(askPrice != 0, "Oracle askPrice is invalid");
            notionalIsolated = int256((currentBalanceUnits * askPrice) / precision);
            uPnLA = int256(initialNotionalUsd) - notionalIsolated;
        }

        return (uPnLA, -uPnLA, notionalIsolated);
    }

    /**
     * @notice Returns the UPnL of a party across all his open positions.
     * @dev This is a naive function, inputs can NOT be trusted. Use cautiously.
     * @dev positionPrices can have an incorrect length.
     * @dev positionPrices can have an arbitrary order.
     * @dev positionPrices can contain forged duplicates.
     */
    function _calculateUPnLCross(PositionPrice[] memory positionPrices, address party)
        private
        view
        returns (int256 uPnLCross, int256 notionalCross)
    {
        AppStorage storage s = LibAppStorage.diamondStorage();
        uint256 numOpenPositionsCross = s.ma._openPositionsCrossLength[party];

        if (numOpenPositionsCross == 0) {
            return (0, 0);
        }

        for (uint256 i = 0; i < positionPrices.length; i++) {
            uint256 positionId = positionPrices[i].positionId;
            uint256 bidPrice = positionPrices[i].bidPrice;
            uint256 askPrice = positionPrices[i].askPrice;

            Position memory position = s.ma._allPositionsMap[positionId];
            require(position.partyA == party || position.partyB == party, "PositionId mismatch");

            (int256 _uPnLIsolatedA, int256 _uPnLIsolatedB, int256 _notionalIsolated) = _calculateUPnLIsolated(
                position.side,
                position.currentBalanceUnits,
                position.initialNotionalUsd,
                bidPrice,
                askPrice
            );

            if (position.partyA == party) {
                uPnLCross += _uPnLIsolatedA;
            } else {
                uPnLCross += _uPnLIsolatedB;
            }

            notionalCross += _notionalIsolated;
        }
    }
}

