// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import { ConstantsInternal } from "./ConstantsInternal.sol";
import { MasterStorage, Position, PositionState } from "./MasterStorage.sol";
import { CloseBase } from "./CloseBase.sol";

contract CloseMarket is CloseBase {
    using MasterStorage for MasterStorage.Layout;

    function requestCloseMarket(uint256 positionId) public {
        MasterStorage.Layout storage s = MasterStorage.layout();
        Position storage position = s.allPositionsMap[positionId];

        require(position.partyA == msg.sender, "Invalid party");
        require(
            position.state == PositionState.OPEN || position.state == PositionState.MARKET_CLOSE_REQUESTED,
            "Invalid position state"
        );
        if (position.state == PositionState.MARKET_CLOSE_REQUESTED) {
            // Prevent spamming
            require(
                position.mutableTimestamp + ConstantsInternal.getRequestTimeout() < block.timestamp,
                "Request Timeout"
            );
        }

        _updatePositionState(position, PositionState.MARKET_CLOSE_REQUESTED);

        emit RequestCloseMarket(positionId, msg.sender, position.partyB);
    }

    function requestCloseMarketAll(uint256[] calldata positionIds) external {
        for (uint256 i = 0; i < positionIds.length; i++) {
            requestCloseMarket(positionIds[i]);
        }
    }

    function cancelCloseMarket(uint256 positionId) external {
        MasterStorage.Layout storage s = MasterStorage.layout();
        Position storage position = s.allPositionsMap[positionId];

        require(position.partyA == msg.sender, "Invalid party");
        require(position.state == PositionState.MARKET_CLOSE_REQUESTED, "Invalid position state");
        require(position.mutableTimestamp + ConstantsInternal.getRequestTimeout() < block.timestamp, "Request Timeout");

        _updatePositionState(position, PositionState.OPEN);

        emit CancelCloseMarket(positionId, msg.sender, position.partyB);
    }
}

