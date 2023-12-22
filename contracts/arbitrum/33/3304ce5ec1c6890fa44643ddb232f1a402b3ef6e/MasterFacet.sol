// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.16;

import { AppStorage, RequestForQuote, Position } from "./LibAppStorage.sol";
import { Decimal } from "./LibDecimal.sol";
import { LibMaster } from "./LibMaster.sol";
import { PositionPrice } from "./LibOracle.sol";
import "./LibEnums.sol";

contract MasterFacet {
    AppStorage internal s;

    event UpdateUuid(uint256 indexed positionId, bytes16 oldUuid, bytes16 newUuid);

    /*-------------------------*
     * PUBLIC WRITE FUNCTIONS *
     *-------------------------*/
    function updateUuid(uint256 positionId, bytes16 uuid) external {
        Position storage position = s.ma._allPositionsMap[positionId];
        require(position.partyB == msg.sender, "Not partyB");
        bytes16 oldUuid = position.uuid;
        position.uuid = uuid;
        emit UpdateUuid(positionId, oldUuid, uuid);
    }

    /*-----------------------*
     * PUBLIC VIEW FUNCTIONS *
     *-----------------------*/

    function getRequestForQuote(uint256 rfqId) external view returns (RequestForQuote memory rfq) {
        return s.ma._requestForQuotesMap[rfqId];
    }

    function getRequestForQuotes(uint256[] calldata rfqIds) external view returns (RequestForQuote[] memory rfqs) {
        uint256 len = rfqIds.length;
        rfqs = new RequestForQuote[](len);

        for (uint256 i = 0; i < len; i++) {
            rfqs[i] = (s.ma._requestForQuotesMap[rfqIds[i]]);
        }
    }

    function getPosition(uint256 positionId) external view returns (Position memory position) {
        return s.ma._allPositionsMap[positionId];
    }

    function getPositions(uint256[] calldata positionIds) external view returns (Position[] memory positions) {
        uint256 len = positionIds.length;
        positions = new Position[](len);

        for (uint256 i = 0; i < len; i++) {
            positions[i] = (s.ma._allPositionsMap[positionIds[i]]);
        }
    }

    function getOpenPositionsIsolatedLength(address party) external view returns (uint256) {
        return s.ma._openPositionsIsolatedLength[party];
    }

    function getOpenPositionsCrossLength(address partyA) external view returns (uint256) {
        return s.ma._openPositionsCrossLength[partyA];
    }

    function getCrossRequestForQuotesLength(address party) external view returns (uint256) {
        return s.ma._crossRequestForQuotesLength[party];
    }

    function calculateUPnLIsolated(
        uint256 positionId,
        uint256 bidPrice,
        uint256 askPrice
    ) external view returns (int256 uPnLA, int256 uPnLB) {
        return LibMaster.calculateUPnLIsolated(positionId, bidPrice, askPrice);
    }

    function calculateUPnLCross(
        PositionPrice[] calldata positionPrices,
        address party
    ) external view returns (int256 uPnLCross) {
        return LibMaster.calculateUPnLCross(positionPrices, party);
    }

    function calculateProtocolFeeAmount(uint256 notionalSize) external view returns (uint256) {
        return LibMaster.calculateProtocolFeeAmount(notionalSize);
    }

    function calculateLiquidationFeeAmount(uint256 notionalSize) external view returns (uint256) {
        return LibMaster.calculateLiquidationFeeAmount(notionalSize);
    }

    function calculateCVAAmount(uint256 notionalSize) external view returns (uint256) {
        return LibMaster.calculateCVAAmount(notionalSize);
    }

    function calculateCrossMarginHealth(
        address party,
        int256 uPnLCross
    ) external view returns (Decimal.D256 memory ratio) {
        return LibMaster.calculateCrossMarginHealth(party, uPnLCross);
    }

    function positionShouldBeLiquidatedIsolated(
        uint256 positionId,
        uint256 bidPrice,
        uint256 askPrice
    ) external view returns (bool shouldBeLiquidated, int256 uPnLA, int256 uPnLB) {
        return LibMaster.positionShouldBeLiquidatedIsolated(positionId, bidPrice, askPrice);
    }

    function partyShouldBeLiquidatedCross(address party, int256 uPnLCross) external view returns (bool) {
        return LibMaster.partyShouldBeLiquidatedCross(party, uPnLCross);
    }
}

