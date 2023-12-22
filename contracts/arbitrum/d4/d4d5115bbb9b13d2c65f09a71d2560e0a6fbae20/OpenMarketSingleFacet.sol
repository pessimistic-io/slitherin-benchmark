// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.16;

import { AppStorage, RequestForQuote, Position } from "./LibAppStorage.sol";
import { LibHedgers } from "./LibHedgers.sol";
import { LibMaster } from "./LibMaster.sol";
import { C } from "./C.sol";
import "./LibEnums.sol";

contract OpenMarketSingleFacet {
    AppStorage internal s;

    event RequestOpenMarketSingle(address indexed partyA, uint256 indexed rfqId);
    event CancelOpenMarketSingle(address indexed partyA, uint256 indexed rfqId);
    event ForceCancelOpenMarketSingle(address indexed partyA, uint256 indexed rfqId);
    event AcceptCancelOpenMarketSingle(address indexed partyB, uint256 indexed rfqId);
    event RejectOpenMarketSingle(address indexed partyB, uint256 indexed rfqId);
    event FillOpenMarketSingle(address indexed partyB, uint256 indexed rfqId, uint256 indexed positionId);

    /*------------------------*
     * PUBLIC WRITE FUNCTIONS *
     *------------------------*/

    function requestOpenMarketSingle(
        address partyB,
        uint256 marketId,
        PositionType positionType,
        Side side,
        uint256 usdAmountToSpend,
        uint16 leverage,
        uint256[2] memory expectedUnits,
        address affiliate
    ) external returns (RequestForQuote memory rfq) {
        require(msg.sender != partyB, "Parties can not be the same");
        (bool validHedger, ) = LibHedgers.isValidHedger(partyB);
        require(validHedger, "Invalid hedger");

        rfq = LibMaster.onRequestForQuote(
            msg.sender,
            partyB,
            marketId,
            positionType,
            OrderType.MARKET,
            HedgerMode.SINGLE,
            side,
            usdAmountToSpend,
            leverage,
            expectedUnits[0],
            expectedUnits[1],
            affiliate
        );

        emit RequestOpenMarketSingle(msg.sender, rfq.rfqId);
    }

    function cancelOpenMarketSingle(uint256 rfqId) external {
        RequestForQuote storage rfq = s.ma._requestForQuotesMap[rfqId];

        require(rfq.partyA == msg.sender, "Invalid party");
        require(rfq.hedgerMode == HedgerMode.SINGLE, "Invalid hedger mode");
        require(rfq.orderType == OrderType.MARKET, "Invalid order type");
        require(rfq.state == RequestForQuoteState.ORPHAN, "Invalid RFQ state");

        _updateRequestForQuoteState(rfq, RequestForQuoteState.CANCELATION_REQUESTED);

        emit CancelOpenMarketSingle(msg.sender, rfqId);
    }

    function forceCancelOpenMarketSingle(uint256 rfqId) external {
        RequestForQuote storage rfq = s.ma._requestForQuotesMap[rfqId];

        require(rfq.partyA == msg.sender, "Invalid party");
        require(rfq.hedgerMode == HedgerMode.SINGLE, "Invalid hedger mode");
        require(rfq.orderType == OrderType.MARKET, "Invalid order type");
        require(rfq.state == RequestForQuoteState.CANCELATION_REQUESTED, "Invalid RFQ state");
        require(rfq.mutableTimestamp + C.getRequestTimeout() < block.timestamp, "Request Timeout");

        _updateRequestForQuoteState(rfq, RequestForQuoteState.CANCELED);
        _onInvalidRequestForQuote(rfq);

        emit ForceCancelOpenMarketSingle(msg.sender, rfqId);
    }

    function acceptCancelOpenMarketSingle(uint256 rfqId) external {
        RequestForQuote storage rfq = s.ma._requestForQuotesMap[rfqId];

        require(rfq.partyB == msg.sender, "Invalid party");
        require(rfq.hedgerMode == HedgerMode.SINGLE, "Invalid hedger mode");
        require(rfq.orderType == OrderType.MARKET, "Invalid order type");
        require(rfq.state == RequestForQuoteState.CANCELATION_REQUESTED, "Invalid RFQ state");

        _updateRequestForQuoteState(rfq, RequestForQuoteState.CANCELED);
        _onInvalidRequestForQuote(rfq);

        emit AcceptCancelOpenMarketSingle(msg.sender, rfqId);
    }

    function rejectOpenMarketSingle(uint256 rfqId) external {
        RequestForQuote storage rfq = s.ma._requestForQuotesMap[rfqId];

        require(rfq.partyB == msg.sender, "Invalid party");
        require(rfq.hedgerMode == HedgerMode.SINGLE, "Invalid hedger mode");
        require(rfq.orderType == OrderType.MARKET, "Invalid order type");
        require(
            rfq.state == RequestForQuoteState.ORPHAN || rfq.state == RequestForQuoteState.CANCELATION_REQUESTED,
            "Invalid RFQ state"
        );

        _updateRequestForQuoteState(rfq, RequestForQuoteState.REJECTED);
        _onInvalidRequestForQuote(rfq);

        emit RejectOpenMarketSingle(msg.sender, rfqId);
    }

    function fillOpenMarketSingle(
        uint256 rfqId,
        uint256 filledAmountUnits,
        uint256 avgPriceUsd,
        bytes16 uuid
    ) external returns (Position memory position) {
        RequestForQuote storage rfq = s.ma._requestForQuotesMap[rfqId];

        require(rfq.partyB == msg.sender, "Invalid party");
        require(rfq.hedgerMode == HedgerMode.SINGLE, "Invalid hedger mode");
        require(rfq.orderType == OrderType.MARKET, "Invalid order type");

        position = LibMaster.onFillOpenMarket(msg.sender, rfqId, filledAmountUnits, avgPriceUsd, uuid);

        emit FillOpenMarketSingle(msg.sender, rfqId, position.positionId);
    }

    /*-------------------------*
     * PRIVATE WRITE FUNCTIONS *
     *-------------------------*/

    function _updateRequestForQuoteState(RequestForQuote storage rfq, RequestForQuoteState state) private {
        rfq.state = state;
        rfq.mutableTimestamp = block.timestamp;
    }

    function _onInvalidRequestForQuote(RequestForQuote memory rfq) private {
        // Return user funds
        uint256 reservedMargin = rfq.lockedMarginA + rfq.protocolFee + rfq.liquidationFee + rfq.cva;
        s.ma._crossLockedMarginReserved[rfq.partyA] -= reservedMargin;
        s.ma._marginBalances[rfq.partyA] += reservedMargin;

        // Decrease the number of active RFQs
        if (rfq.positionType == PositionType.CROSS) {
            s.ma._crossRequestForQuotesLength[rfq.partyA]--;
        }
    }
}

