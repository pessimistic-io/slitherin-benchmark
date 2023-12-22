// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.16;

import { AppStorage, LibAppStorage, Position } from "./LibAppStorage.sol";
import { LibMaster } from "./LibMaster.sol";
import { LibOracle, SchnorrSign } from "./LibOracle.sol";
import { C } from "./C.sol";
import "./LibEnums.sol";

/**
 * Close a Position through a Market order.
 * @dev Can only be done via the original partyB.
 */
contract CloseMarketFacet {
    AppStorage internal s;

    event RequestCloseMarket(address indexed partyA, uint256 indexed positionId);
    event CancelCloseMarket(address indexed partyA, uint256 indexed positionId);
    event ForceCancelCloseMarket(address indexed partyA, uint256 indexed positionId);
    event AcceptCancelCloseMarket(address indexed partyB, uint256 indexed positionId);
    event RejectCloseMarket(address indexed partyB, uint256 indexed positionId);
    event FillCloseMarket(address indexed partyB, uint256 indexed positionId);

    /*------------------------*
     * PUBLIC WRITE FUNCTIONS *
     *------------------------*/

    function requestCloseMarket(uint256 positionId) external {
        Position storage position = s.ma._allPositionsMap[positionId];

        require(position.partyA == msg.sender, "Invalid party");
        require(
            position.state == PositionState.OPEN || position.state == PositionState.MARKET_CLOSE_REQUESTED,
            "Invalid position state"
        );

        _updatePositionState(position, PositionState.MARKET_CLOSE_REQUESTED);

        emit RequestCloseMarket(msg.sender, positionId);
    }

    function cancelCloseMarket(uint256 positionId) external {
        Position storage position = s.ma._allPositionsMap[positionId];

        require(position.partyA == msg.sender, "Invalid party");
        require(position.state == PositionState.MARKET_CLOSE_REQUESTED, "Invalid position state");

        _updatePositionState(position, PositionState.MARKET_CLOSE_CANCELATION_REQUESTED);

        emit CancelCloseMarket(msg.sender, positionId);
    }

    function forceCancelCloseMarket(uint256 positionId) external {
        Position storage position = s.ma._allPositionsMap[positionId];

        require(position.partyA == msg.sender, "Invalid party");
        require(position.state == PositionState.MARKET_CLOSE_CANCELATION_REQUESTED, "Invalid position state");
        require(position.mutableTimestamp + C.getRequestTimeout() < block.timestamp, "Request Timeout");

        _updatePositionState(position, PositionState.OPEN);

        emit ForceCancelCloseMarket(msg.sender, positionId);
    }

    function acceptCancelCloseMarket(uint256 positionId) external {
        Position storage position = s.ma._allPositionsMap[positionId];

        require(position.partyB == msg.sender, "Invalid party");
        require(position.state == PositionState.MARKET_CLOSE_CANCELATION_REQUESTED, "Invalid position state");

        _updatePositionState(position, PositionState.OPEN);

        emit AcceptCancelCloseMarket(msg.sender, positionId);
    }

    function rejectCloseMarket(uint256 positionId) external {
        Position storage position = s.ma._allPositionsMap[positionId];

        require(position.partyB == msg.sender, "Invalid party");
        require(position.state == PositionState.MARKET_CLOSE_REQUESTED, "Invalid position state");

        _updatePositionState(position, PositionState.OPEN);

        emit RejectCloseMarket(msg.sender, positionId);
    }

    /// @dev TODO: upgrade this to use oracle signatures
    function fillCloseMarket(uint256 positionId, uint256 avgPriceUsd) external {
        Position storage position = s.ma._allPositionsMap[positionId];

        require(position.partyB == msg.sender, "Invalid party");
        require(position.state == PositionState.MARKET_CLOSE_REQUESTED, "Invalid position state");

        // Handle the fill
        LibMaster.onFillCloseMarket(positionId, LibOracle.createPositionPrice(positionId, avgPriceUsd, avgPriceUsd));

        emit FillCloseMarket(msg.sender, positionId);
    }

    // function fillCloseMarket(
    //     uint256 positionId,
    //     uint256 bidPrice,
    //     uint256 askPrice,
    //     bytes calldata reqId,
    //     uint256 timestamp,
    //     SchnorrSign[] calldata sigs
    // ) external {
    //     Position storage position = s.ma._allPositionsMap[positionId];

    //     require(position.partyB == msg.sender, "Invalid party");
    //     require(position.state == PositionState.MARKET_CLOSE_REQUESTED, "Invalid position state");

    //     // Verify oracle signatures
    //     LibOracle.verifyPositionPriceOrThrow(positionId, bidPrice, askPrice, reqId, timestamp, sigs);

    //     // Handle the fill
    //     LibMaster.onFillCloseMarket(positionId, LibOracle.createPositionPrice(positionId, bidPrice, askPrice));

    //     emit FillCloseMarket(msg.sender, positionId);
    // }

    /*-------------------------*
     * PRIVATE WRITE FUNCTIONS *
     *-------------------------*/

    function _updatePositionState(Position storage position, PositionState state) private {
        position.state = state;
        position.mutableTimestamp = block.timestamp;
    }
}

