// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import { OrderType } from "./LibEnums.sol";
import { OracleInternal } from "./OracleInternal.sol";
import { MasterStorage, Position, PositionState } from "./MasterStorage.sol";
import { CloseBase } from "./CloseBase.sol";

contract ClosePosition is CloseBase {
    using MasterStorage for MasterStorage.Layout;

    function closePosition(uint256 positionId, uint256 avgPriceUsd) external {
        Position memory position = MasterStorage.layout().allPositionsMap[positionId];

        if (position.state == PositionState.MARKET_CLOSE_REQUESTED) {
            _closeMarket(position, avgPriceUsd);
        } else {
            revert("Other modes not implemented yet");
        }
    }

    function _closeMarket(Position memory position, uint256 avgPriceUsd) private {
        require(position.partyB == msg.sender, "Invalid party");
        _onClosePosition(
            position.positionId,
            OracleInternal.createPositionPrice(position.positionId, avgPriceUsd, avgPriceUsd)
        );
    }
}

