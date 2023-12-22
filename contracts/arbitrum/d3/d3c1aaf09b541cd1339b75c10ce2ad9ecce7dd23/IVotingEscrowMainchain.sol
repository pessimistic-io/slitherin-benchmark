// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.20;

import "./IVotingEscrow.sol";
import "./VeHistoryLib.sol";

interface IVotingEscrowMainchain is IVotingEscrow {
    // ============= EVENTS =============

    event NewLockPosition(address indexed user, uint128 amount, uint128 expiry);

    event Withdraw(address indexed user, uint128 amount);

    event BroadcastTotalSupply(VeBalance newTotalSupply, uint256[] chainIds);

    event BroadcastUserPosition(address indexed user, uint256[] chainIds);

    // ============= ACTIONS =============

    function increaseLockPosition(uint128 additionalAmountToLock, uint128 expiry) external returns (uint128);

    function withdraw() external returns (uint128);

    function totalSupplyAt(uint128 timestamp) external view returns (uint128);

    function getUserHistoryLength(address user) external view returns (uint256);

    function getUserHistoryAt(address user, uint256 index) external view returns (Checkpoint memory);
}

