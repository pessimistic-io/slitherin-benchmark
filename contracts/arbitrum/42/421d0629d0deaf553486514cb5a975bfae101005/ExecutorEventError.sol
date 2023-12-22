// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.13;

interface ExecutorEventError {
    // ---------------------------------------------------------------------------------------- //
    // *************************************** Events ***************************************** //
    // ---------------------------------------------------------------------------------------- //

    event ReportExecuted(address pool, uint256 poolId, uint256 reportId);

    event NewPoolExecuted(
        address poolAddress,
        uint256 proposalId,
        address protocol
    );

    // ---------------------------------------------------------------------------------------- //
    // *************************************** Errors ***************************************** //
    // ---------------------------------------------------------------------------------------- //

    error Executor__ReportNotSettled();
    error Executor__ReportNotPassed();
    error Executor__ProposalNotSettled();
    error Executor__ProposalNotPassed();
    error Executor__AlreadyExecuted();
}

