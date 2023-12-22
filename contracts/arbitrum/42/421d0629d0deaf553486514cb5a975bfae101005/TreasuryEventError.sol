// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.13;

abstract contract TreasuryEventError {
    // ---------------------------------------------------------------------------------------- //
    // *************************************** Events ***************************************** //
    // ---------------------------------------------------------------------------------------- //

    event ReporterRewarded(address indexed reporter, uint256 amount);

    event NewIncomeToTreasury(uint256 indexed poolId, uint256 amount);

    event ClaimedByOwner(uint256 amount);

    // ---------------------------------------------------------------------------------------- //
    // *************************************** Errors ***************************************** //
    // ---------------------------------------------------------------------------------------- //

    error Treasury__OnlyExecutor();

    error Treasury__OnlyPolicyCenter();

    error Treasury__OnlyOwner();
}

