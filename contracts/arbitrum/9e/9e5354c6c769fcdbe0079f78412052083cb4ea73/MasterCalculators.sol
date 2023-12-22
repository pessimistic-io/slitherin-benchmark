// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import { Side } from "./LibEnums.sol";
import { Decimal } from "./LibDecimal.sol";
import { PositionPrice } from "./OracleStorage.sol";
import { ConstantsInternal } from "./ConstantsInternal.sol";
import { MarketsInternal } from "./MarketsInternal.sol";
import { MasterStorage, Position } from "./MasterStorage.sol";

library MasterCalculators {
    using Decimal for Decimal.D256;
    using MasterStorage for MasterStorage.Layout;

    /**
     * @notice Returns the UPnL for a specific position.
     * @dev This is a naive function, inputs can not be trusted. Use cautiously.
     */
    function calculateUPnLIsolated(
        uint256 positionId,
        uint256 bidPrice,
        uint256 askPrice
    ) internal view returns (int256 uPnLA, int256 uPnLB) {
        MasterStorage.Layout storage s = MasterStorage.layout();
        Position memory position = s.allPositionsMap[positionId];

        (uPnLA, uPnLB) = _calculateUPnLIsolated(
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
    function calculateUPnLCross(
        PositionPrice[] memory positionPrices,
        address party
    ) internal view returns (int256 uPnLCross) {
        return _calculateUPnLCross(positionPrices, party);
    }

    function calculateProtocolFeeAmount(uint256 marketId, uint256 notionalUsd) internal view returns (uint256) {
        return Decimal.from(notionalUsd).mul(MarketsInternal.getMarketProtocolFee(marketId)).asUint256();
    }

    function calculateLiquidationFeeAmount(uint256 notionalUsd) internal view returns (uint256) {
        return Decimal.from(notionalUsd).mul(ConstantsInternal.getLiquidationFee()).asUint256();
    }

    function calculateCVAAmount(uint256 notionalSize) internal view returns (uint256) {
        return Decimal.from(notionalSize).mul(ConstantsInternal.getCVA()).asUint256();
    }

    function calculateCrossMarginHealth(
        address party,
        int256 uPnLCross
    ) internal view returns (Decimal.D256 memory ratio) {
        MasterStorage.Layout storage s = MasterStorage.layout();

        uint256 lockedMargin = s.crossLockedMargin[party];
        uint256 openPositions = s.openPositionsCrossLength[party];

        if (lockedMargin == 0 && openPositions == 0) {
            return Decimal.ratio(1, 1);
        } else if (lockedMargin == 0) {
            return Decimal.zero();
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

    /* ========== PRIVATE ========== */

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
    ) private pure returns (int256 uPnLA, int256 uPnLB) {
        if (currentBalanceUnits == 0) return (0, 0);

        uint256 precision = ConstantsInternal.getPrecision();
        if (side == Side.BUY) {
            require(bidPrice != 0, "Oracle bidPrice is invalid");
            int256 notionalIsolatedA = int256((currentBalanceUnits * bidPrice) / precision);
            uPnLA = notionalIsolatedA - int256(initialNotionalUsd);
        } else {
            require(askPrice != 0, "Oracle askPrice is invalid");
            int256 notionalIsolatedA = int256((currentBalanceUnits * askPrice) / precision);
            uPnLA = int256(initialNotionalUsd) - notionalIsolatedA;
        }

        return (uPnLA, -uPnLA);
    }

    /**
     * @notice Returns the UPnL of a party across all his open positions.
     * @dev This is a naive function, inputs can NOT be trusted. Use cautiously.
     * @dev positionPrices can have an incorrect length.
     * @dev positionPrices can have an arbitrary order.
     * @dev positionPrices can contain forged duplicates.
     */
    function _calculateUPnLCross(
        PositionPrice[] memory positionPrices,
        address party
    ) private view returns (int256 uPnLCrossA) {
        MasterStorage.Layout storage s = MasterStorage.layout();

        for (uint256 i = 0; i < positionPrices.length; i++) {
            uint256 positionId = positionPrices[i].positionId;
            uint256 bidPrice = positionPrices[i].bidPrice;
            uint256 askPrice = positionPrices[i].askPrice;

            Position memory position = s.allPositionsMap[positionId];
            require(position.partyA == party, "PositionId mismatch");

            (int256 _uPnLIsolatedA, ) = _calculateUPnLIsolated(
                position.side,
                position.currentBalanceUnits,
                position.initialNotionalUsd,
                bidPrice,
                askPrice
            );

            uPnLCrossA += _uPnLIsolatedA;
        }
    }
}

