// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.16;

import { AppStorage, RequestForQuote, Position, Fill } from "./LibAppStorage.sol";
import { Decimal } from "./LibDecimal.sol";
import { LibMaster } from "./LibMaster.sol";
import { PositionPrice } from "./LibOracle.sol";
import "./LibEnums.sol";

contract MasterFacet {
    AppStorage internal s;

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

    function getOpenRequestForQuoteIds(address party) external view returns (uint256[] memory rfqIds) {
        return s.ma._openRequestForQuotesList[party];
    }

    function getOpenRequestForQuotes(address party) external view returns (RequestForQuote[] memory rfqs) {
        uint256 len = s.ma._openRequestForQuotesList[party].length;
        rfqs = new RequestForQuote[](len);

        for (uint256 i = 0; i < len; i++) {
            rfqs[i] = (s.ma._requestForQuotesMap[s.ma._openRequestForQuotesList[party][i]]);
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

    function getOpenPositionsIsolated(address party) external view returns (Position[] memory openPositionsIsolated) {
        return LibMaster.getOpenPositionsIsolated(party);
    }

    function getOpenPositionsCross(address party) external view returns (Position[] memory openPositionsCross) {
        return LibMaster.getOpenPositionsCross(party);
    }

    function getOpenPositionIdsIsolated(address party) external view returns (uint256[] memory positionIds) {
        return s.ma._openPositionsIsolatedList[party];
    }

    function getOpenPositionIdsCross(address party) external view returns (uint256[] memory positionIds) {
        return s.ma._openPositionsCrossList[party];
    }

    function getPositionFills(uint256 positionId) external view returns (Fill[] memory fills) {
        return s.ma._positionFills[positionId];
    }

    function calculateUPnLIsolated(
        uint256 positionId,
        uint256 bidPrice,
        uint256 askPrice
    ) external view returns (int256 uPnLA, int256 uPnLB) {
        return LibMaster.calculateUPnLIsolated(positionId, bidPrice, askPrice);
    }

    function calculateUPnLCross(PositionPrice[] calldata positionPrices, address party)
        external
        view
        returns (int256 uPnLCross, int256 notionalCross)
    {
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

    function calculateCrossMarginHealth(uint256 lockedMargin, int256 uPnL)
        external
        pure
        returns (Decimal.D256 memory ratio)
    {
        return LibMaster.calculateCrossMarginHealth(lockedMargin, uPnL);
    }

    function positionShouldBeLiquidatedIsolated(
        uint256 positionId,
        uint256 bidPrice,
        uint256 askPrice
    )
        external
        view
        returns (
            bool shouldLiquidated,
            int256 pnlA,
            int256 pnlB
        )
    {
        return LibMaster.positionShouldBeLiquidatedIsolated(positionId, bidPrice, askPrice);
    }

    function partyShouldBeLiquidatedCross(address party, int256 uPnLCross) external view returns (bool) {
        return LibMaster.partyShouldBeLiquidatedCross(party, uPnLCross);
    }
}

