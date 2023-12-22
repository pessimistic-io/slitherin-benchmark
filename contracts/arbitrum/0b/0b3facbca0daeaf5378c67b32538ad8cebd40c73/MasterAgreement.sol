// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import { Decimal } from "./LibDecimal.sol";
import { PositionPrice } from "./OracleInternal.sol";
import { MasterCalculators } from "./MasterCalculators.sol";
import { MasterStorage, RequestForQuote, Position } from "./MasterStorage.sol";

contract MasterAgreement {
    using MasterStorage for MasterStorage.Layout;

    event UpdateUuid(uint256 indexed positionId, bytes16 oldUuid, bytes16 newUuid);

    /* ========== WRITES ========== */

    function updateUuid(uint256 positionId, bytes16 uuid) external {
        MasterStorage.Layout storage s = MasterStorage.layout();

        Position storage position = s.allPositionsMap[positionId];
        require(position.partyB == msg.sender, "Not partyB");
        bytes16 oldUuid = position.uuid;
        position.uuid = uuid;
        emit UpdateUuid(positionId, oldUuid, uuid);
    }

    /* ========== VIEWS ========== */

    function getRequestForQuote(uint256 rfqId) external view returns (RequestForQuote memory rfq) {
        return MasterStorage.layout().requestForQuotesMap[rfqId];
    }

    function getRequestForQuotes(uint256[] calldata rfqIds) external view returns (RequestForQuote[] memory rfqs) {
        uint256 len = rfqIds.length;
        rfqs = new RequestForQuote[](len);

        for (uint256 i = 0; i < len; i++) {
            rfqs[i] = (MasterStorage.layout().requestForQuotesMap[rfqIds[i]]);
        }
    }

    function getPosition(uint256 positionId) external view returns (Position memory position) {
        return MasterStorage.layout().allPositionsMap[positionId];
    }

    function getPositions(uint256[] calldata positionIds) external view returns (Position[] memory positions) {
        uint256 len = positionIds.length;
        positions = new Position[](len);

        for (uint256 i = 0; i < len; i++) {
            positions[i] = (MasterStorage.layout().allPositionsMap[positionIds[i]]);
        }
    }

    function getOpenPositionsIsolatedLength(address party) external view returns (uint256) {
        return MasterStorage.layout().openPositionsIsolatedLength[party];
    }

    function getOpenPositionsCrossLength(address partyA) external view returns (uint256) {
        return MasterStorage.layout().openPositionsCrossLength[partyA];
    }

    function getCrossRequestForQuotesLength(address party) external view returns (uint256) {
        return MasterStorage.layout().crossRequestForQuotesLength[party];
    }

    function calculateUPnLIsolated(
        uint256 positionId,
        uint256 bidPrice,
        uint256 askPrice
    ) external view returns (int256 uPnLA, int256 uPnLB) {
        return MasterCalculators.calculateUPnLIsolated(positionId, bidPrice, askPrice);
    }

    function calculateUPnLCross(
        PositionPrice[] calldata positionPrices,
        address party
    ) external view returns (int256 uPnLCross) {
        return MasterCalculators.calculateUPnLCross(positionPrices, party);
    }

    function calculateProtocolFeeAmount(uint256 marketId, uint256 notionalSize) external view returns (uint256) {
        return MasterCalculators.calculateProtocolFeeAmount(marketId, notionalSize);
    }

    function calculateLiquidationFeeAmount(uint256 notionalSize) external view returns (uint256) {
        return MasterCalculators.calculateLiquidationFeeAmount(notionalSize);
    }

    function calculateCVAAmount(uint256 notionalSize) external view returns (uint256) {
        return MasterCalculators.calculateCVAAmount(notionalSize);
    }

    function calculateCrossMarginHealth(
        address party,
        int256 uPnLCross
    ) external view returns (Decimal.D256 memory ratio) {
        return MasterCalculators.calculateCrossMarginHealth(party, uPnLCross);
    }
}

