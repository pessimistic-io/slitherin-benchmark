// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

interface ICloseEvents {
    event RequestClosePosition(uint256 indexed positionId, address partyA, address partyB);
    event CancelClosePosition(uint256 indexed positionId, address partyA, address partyB);
    event ClosePosition(
        uint256 indexed positionId,
        address partyA,
        address partyB,
        uint256 amountUnits,
        uint256 avgPriceUsd
    );
}

