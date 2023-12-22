// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import { Decimal } from "./LibDecimal.sol";
import { PositionType } from "./LibEnums.sol";
import { MasterStorage, Position } from "./MasterStorage.sol";
import { MasterCalculators } from "./MasterCalculators.sol";

library LiquidationsInternal {
    using Decimal for Decimal.D256;
    using MasterStorage for MasterStorage.Layout;

    function positionShouldBeLiquidatedIsolated(
        uint256 positionId,
        uint256 bidPrice,
        uint256 askPrice
    ) internal view returns (bool shouldBeLiquidated, int256 uPnLA, int256 uPnLB) {
        MasterStorage.Layout storage s = MasterStorage.layout();
        Position memory position = s.allPositionsMap[positionId];

        (uPnLA, uPnLB) = MasterCalculators.calculateUPnLIsolated(positionId, bidPrice, askPrice);
        shouldBeLiquidated = uPnLA <= 0
            ? uint256(uPnLB) >= position.lockedMarginA
            : uint256(uPnLA) >= position.lockedMarginB;
    }

    function partyShouldBeLiquidatedCross(address party, int256 uPnLCross) internal view returns (bool) {
        Decimal.D256 memory ratio = MasterCalculators.calculateCrossMarginHealth(party, uPnLCross);
        return ratio.isZero();
    }
}

