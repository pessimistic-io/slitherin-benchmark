// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

interface IOpenEvents {
    event RequestForQuoteNew(uint256 indexed rfqId, address partyA, address partyB);
    event RequestForQuoteCanceled(uint256 indexed rfqId, address partyA, address partyB);
    event OpenPosition(
        uint256 indexed rfqId,
        uint256 indexed positionId,
        address partyA,
        address partyB,
        uint256 amountUnits,
        uint256 avgPriceUsd
    );
}

