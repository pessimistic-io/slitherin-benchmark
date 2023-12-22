// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import { PositionType, OrderType, HedgerMode, Side } from "./LibEnums.sol";
import { MarketsInternal } from "./MarketsInternal.sol";
import { ConstantsInternal } from "./ConstantsInternal.sol";
import { MasterStorage, RequestForQuote, RequestForQuoteState, Position, PositionState } from "./MasterStorage.sol";
import { MasterCalculators } from "./MasterCalculators.sol";
import { IOpenEvents } from "./IOpenEvents.sol";

abstract contract OpenBase is IOpenEvents {
    using MasterStorage for MasterStorage.Layout;

    function _onRequestForQuote(
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
        uint256 maxExpectedUnits,
        address affiliate
    ) internal returns (RequestForQuote memory rfq) {
        MasterStorage.Layout storage s = MasterStorage.layout();

        // This inherently validates the existence of a market as well.
        require(MarketsInternal.isActiveMarket(marketId), "Market not active");

        if (positionType == PositionType.CROSS) {
            uint256 numOpenPositionsCross = s.openPositionsCrossLength[partyA];
            uint256 numOpenRfqsCross = s.crossRequestForQuotesLength[partyA];
            require(
                numOpenPositionsCross + numOpenRfqsCross < ConstantsInternal.getMaxOpenPositionsCross(),
                "Max open positions cross reached"
            );
        }

        require(usdAmountToSpend > 0, "Amount cannot be zero");
        uint256 notionalUsd = usdAmountToSpend * leverage;
        uint256 protocolFee = MasterCalculators.calculateProtocolFeeAmount(marketId, notionalUsd);
        uint256 liquidationFee = MasterCalculators.calculateLiquidationFeeAmount(notionalUsd);
        uint256 cva = MasterCalculators.calculateCVAAmount(notionalUsd);
        uint256 amount = usdAmountToSpend + protocolFee + liquidationFee + cva;

        require(amount <= s.marginBalances[partyA], "Insufficient margin balance");
        s.marginBalances[partyA] -= amount;
        s.crossLockedMarginReserved[partyA] += amount; // TODO: rename this to lockedMarginReserved

        // Create the RFQ
        uint256 currentRfqId = s.requestForQuotesLength + 1;
        rfq = RequestForQuote({
            creationTimestamp: block.timestamp,
            mutableTimestamp: block.timestamp,
            rfqId: currentRfqId,
            state: RequestForQuoteState.NEW,
            positionType: positionType,
            orderType: orderType,
            partyA: partyA,
            partyB: partyB,
            hedgerMode: hedgerMode,
            marketId: marketId,
            side: side,
            notionalUsd: notionalUsd,
            lockedMarginA: usdAmountToSpend,
            protocolFee: protocolFee,
            liquidationFee: liquidationFee,
            cva: cva,
            minExpectedUnits: minExpectedUnits,
            maxExpectedUnits: maxExpectedUnits,
            affiliate: affiliate
        });

        s.requestForQuotesMap[currentRfqId] = rfq;
        s.requestForQuotesLength++;

        // Increase the number of active RFQs
        if (positionType == PositionType.CROSS) {
            s.crossRequestForQuotesLength[partyA]++;
        }
    }

    function _openPositionMarket(
        address partyB,
        uint256 rfqId,
        uint256 filledAmountUnits,
        bytes16 uuid,
        uint256 lockedMarginB
    ) internal returns (Position memory position) {
        MasterStorage.Layout storage s = MasterStorage.layout();
        RequestForQuote storage rfq = s.requestForQuotesMap[rfqId];

        require(rfq.state == RequestForQuoteState.NEW, "Invalid RFQ state");
        require(rfq.minExpectedUnits <= filledAmountUnits, "Invalid min filled amount");
        require(rfq.maxExpectedUnits >= filledAmountUnits, "Invalid max filled amount");

        // Update the RFQ
        _updateRequestForQuoteState(rfq, RequestForQuoteState.ACCEPTED);

        // Create the Position
        uint256 currentPositionId = s.allPositionsLength + 1;
        position = Position({
            creationTimestamp: block.timestamp,
            mutableTimestamp: block.timestamp,
            positionId: currentPositionId,
            uuid: uuid,
            state: PositionState.OPEN,
            positionType: rfq.positionType,
            marketId: rfq.marketId,
            partyA: rfq.partyA,
            partyB: rfq.partyB,
            side: rfq.side,
            lockedMarginA: rfq.lockedMarginA,
            lockedMarginB: lockedMarginB,
            protocolFeePaid: rfq.protocolFee,
            liquidationFee: rfq.liquidationFee,
            cva: rfq.cva,
            currentBalanceUnits: filledAmountUnits,
            initialNotionalUsd: rfq.notionalUsd,
            affiliate: rfq.affiliate
        });

        // Update global mappings
        s.allPositionsMap[currentPositionId] = position;
        s.allPositionsLength++;

        // Transfer partyA's collateral
        uint256 deductableMarginA = rfq.lockedMarginA + rfq.protocolFee + rfq.liquidationFee + rfq.cva;
        s.crossLockedMarginReserved[rfq.partyA] -= deductableMarginA; // TODO: rename this to lockedMarginReserved

        // Transfer partyB's collateral
        uint256 deductableMarginB = lockedMarginB + rfq.liquidationFee + rfq.cva; // hedger doesn't pay protocolFee
        require(deductableMarginB <= s.marginBalances[partyB], "Insufficient margin balance");
        s.marginBalances[partyB] -= deductableMarginB;

        // Collect the fee paid by partyA
        s.accountBalances[address(this)] += rfq.protocolFee;

        if (rfq.positionType == PositionType.CROSS) {
            // Increase the number of open positions
            s.openPositionsCrossLength[rfq.partyA]++;

            // Decrease the number of active RFQs
            s.crossRequestForQuotesLength[rfq.partyA]--;

            // Lock margins
            s.crossLockedMargin[rfq.partyA] += rfq.lockedMarginA;
            s.crossLockedMargin[partyB] += lockedMarginB;
        }
    }

    function _updateRequestForQuoteState(RequestForQuote storage rfq, RequestForQuoteState state) internal {
        rfq.state = state;
        rfq.mutableTimestamp = block.timestamp;
    }

    function _cancelRequestForQuote(RequestForQuote memory rfq) internal {
        MasterStorage.Layout storage s = MasterStorage.layout();

        // Return user funds
        uint256 reservedMargin = rfq.lockedMarginA + rfq.protocolFee + rfq.liquidationFee + rfq.cva;
        s.crossLockedMarginReserved[rfq.partyA] -= reservedMargin; // TODO: rename this to lockedMarginReserved
        s.marginBalances[rfq.partyA] += reservedMargin;

        // Decrease the number of active RFQs
        if (rfq.positionType == PositionType.CROSS) {
            s.crossRequestForQuotesLength[rfq.partyA]--;
        }
    }
}

