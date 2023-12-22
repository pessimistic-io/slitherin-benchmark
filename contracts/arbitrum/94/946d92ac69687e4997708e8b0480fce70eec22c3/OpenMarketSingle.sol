// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import { PositionType, Side, OrderType, HedgerMode } from "./LibEnums.sol";
import { HedgersInternal } from "./HedgersInternal.sol";
import { ConstantsInternal } from "./ConstantsInternal.sol";
import { MasterStorage, RequestForQuote, RequestForQuoteState } from "./MasterStorage.sol";
import { OpenBase } from "./OpenBase.sol";

contract OpenMarketSingle is OpenBase {
    using MasterStorage for MasterStorage.Layout;

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
        HedgersInternal.getHedgerByAddressOrThrow(partyB);

        rfq = _onRequestForQuote(
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

        emit RequestForQuoteNew(rfq.rfqId, msg.sender, partyB);
    }

    function cancelOpenMarketSingle(uint256 rfqId) public {
        RequestForQuote storage rfq = MasterStorage.layout().requestForQuotesMap[rfqId];

        require(rfq.partyA == msg.sender, "Invalid party");
        require(rfq.orderType == OrderType.MARKET, "Invalid order type");
        require(rfq.hedgerMode == HedgerMode.SINGLE, "Invalid hedger mode");
        require(rfq.state == RequestForQuoteState.NEW, "Invalid RFQ state");
        require(rfq.mutableTimestamp + ConstantsInternal.getRequestTimeout() < block.timestamp, "Request Timeout");

        _updateRequestForQuoteState(rfq, RequestForQuoteState.CANCELED);
        _cancelRequestForQuote(rfq);

        emit RequestForQuoteCanceled(rfqId, msg.sender, rfq.partyB);
    }

    function cancelAllOpenMarketSingle(uint256[] calldata rfqIds) external {
        for (uint256 i = 0; i < rfqIds.length; i++) {
            cancelOpenMarketSingle(rfqIds[i]);
        }
    }
}

