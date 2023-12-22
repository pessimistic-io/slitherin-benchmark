// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

interface IMasterAgreement {
    /* ========== ACCOUNTS ========== */
    function deposit(uint256 amount) external;

    function withdraw(uint256 amount) external;

    function allocate(uint256 amount) external;

    function deallocate(uint256 amount) external;

    function depositAndAllocate(uint256 amount) external;

    function deallocateAndWithdraw(uint256 amount) external;

    /* ========== HEDGERS ========== */
    function enlist(string[] calldata pricingWssURLs, string[] calldata marketsHttpsURLs) external;
}

