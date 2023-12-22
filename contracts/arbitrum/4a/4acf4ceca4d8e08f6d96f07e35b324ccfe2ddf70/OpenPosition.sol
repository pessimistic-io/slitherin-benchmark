// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import { OrderType, HedgerMode } from "./LibEnums.sol";
import { MasterStorage, RequestForQuote, Position } from "./MasterStorage.sol";
import { OpenBase } from "./OpenBase.sol";

contract OpenPosition is OpenBase {
    using MasterStorage for MasterStorage.Layout;

    function openPosition(
        uint256 rfqId,
        uint256 filledAmountUnits,
        uint256 avgPriceUsd,
        bytes16 uuid
    ) external returns (Position memory position) {
        RequestForQuote storage rfq = MasterStorage.layout().requestForQuotesMap[rfqId];

        if (rfq.hedgerMode == HedgerMode.SINGLE && rfq.orderType == OrderType.MARKET) {
            position = _openPositionMarketSingle(rfq, filledAmountUnits, uuid);
        } else {
            revert("Other modes not implemented yet");
        }

        emit OpenPosition(rfq.rfqId, position.positionId, rfq.partyA, rfq.partyB, filledAmountUnits, avgPriceUsd);
    }

    function _openPositionMarketSingle(
        RequestForQuote memory rfq,
        uint256 filledAmountUnits,
        bytes16 uuid
    ) private returns (Position memory position) {
        require(rfq.partyB == msg.sender, "Invalid party");
        return _openPositionMarket(msg.sender, rfq.rfqId, filledAmountUnits, uuid);
    }
}

