// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import { OracleInternal } from "./OracleInternal.sol";
import { AccessControlInternal } from "./AccessControlInternal.sol";
import { MasterStorage, Position } from "./MasterStorage.sol";
import { CloseBase } from "./CloseBase.sol";

contract ClosePositionOwnable is CloseBase, AccessControlInternal {
    using MasterStorage for MasterStorage.Layout;

    function emergencyClosePosition(uint256 positionId, uint256 priceUsd) public onlyRole(EMERGENCY_ROLE) {
        Position memory position = MasterStorage.layout().allPositionsMap[positionId];
        _onClosePosition(
            position.positionId,
            OracleInternal.createPositionPrice(position.positionId, priceUsd, priceUsd)
        );
    }

    function emergencyClosePositions(
        uint256[] calldata positionIds,
        uint256[] calldata pricesUsd
    ) external onlyRole(EMERGENCY_ROLE) {
        for (uint256 i = 0; i < positionIds.length; i++) {
            emergencyClosePosition(positionIds[i], pricesUsd[i]);
        }
    }
}

