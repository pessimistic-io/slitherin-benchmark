// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

interface ILiquidationsEvents {
    event Liquidate(
        uint256 indexed positionId,
        address partyA,
        address partyB,
        address targetParty,
        uint256 amountUnits,
        uint256 priceUsd
    );
}

