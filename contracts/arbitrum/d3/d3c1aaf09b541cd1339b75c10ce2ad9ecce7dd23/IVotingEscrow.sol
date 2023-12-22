// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.20;

interface IVotingEscrow {
    // ============= USER INFO =============

    function balanceOf(address user) external view returns (uint128);

    function balanceOfAt(address user, uint128 timestamp) external view returns (uint128);

    function positionData(address user) external view returns (uint128 amount, uint128 expiry);

    // ============= META DATA =============

    function totalSupplyStored() external view returns (uint128);

    function totalSupplyCurrent() external returns (uint128);

    function totalSupplyAndBalanceCurrent(address user) external returns (uint128, uint128);
}

