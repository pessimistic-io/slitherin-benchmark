// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

interface IMasterAgreement {
    /* ========== ACCOUNTS - WRITES ========== */
    function deposit(uint256 amount) external;

    function withdraw(uint256 amount) external;

    function allocate(uint256 amount) external;

    function deallocate(uint256 amount) external;

    function depositAndAllocate(uint256 amount) external;

    function deallocateAndWithdraw(uint256 amount) external;

    function addFreeMarginIsolated(uint256 amount, uint256 positionId) external;

    function addFreeMarginCross(uint256 amount) external;

    function removeFreeMarginCross() external;

    /* ========== ACCOUNTS - VIEWS ========== */

    function getAccountBalance(address party) external view returns (uint256);

    function getMarginBalance(address party) external view returns (uint256);

    function getLockedMarginIsolated(address party, uint256 positionId) external view returns (uint256);

    function getLockedMarginCross(address party) external view returns (uint256);

    function getLockedMarginReserved(address party) external view returns (uint256);

    /* ========== TRADES ========== */

    function openPosition(
        uint256 rfqId,
        uint256 filledAmountUnits,
        uint256 avgPriceUsd,
        bytes16 uuid,
        uint256 lockedMarginB
    ) external;

    function closePosition(uint256 positionId, uint256 avgPriceUsd) external;

    /* ========== MASTERAGREEMENT ========== */

    function updateUuid(uint256 positionId, bytes16 uuid) external;

    /* ========== HEDGERS ========== */

    function enlist() external;
}

