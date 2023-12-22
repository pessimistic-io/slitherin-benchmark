// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.13;

interface IncidentReportEventError {
    // ---------------------------------------------------------------------------------------- //
    // *************************************** Events ***************************************** //
    // ---------------------------------------------------------------------------------------- //

    event ReportCreated(
        uint256 reportId,
        uint256 indexed poolId,
        uint256 reportTimestamp,
        address indexed reporter,
        uint256 payout
    );

    event ReportVotingStart(uint256 reportId, uint256 startTimestamp);

    event ReportClosed(uint256 reportId, uint256 closeTimestamp);

    event ReportVoted(
        uint256 reportId,
        address indexed user,
        uint256 voteFor,
        uint256 amount
    );

    event ReportSettled(uint256 reportId, uint256 result);

    event ReportExtended(uint256 reportId, uint256 round);

    event ReportFailed(uint256 reportId);

    event DebtPaid(
        address payer,
        address user,
        uint256 debt,
        uint256 unlockAmount
    );

    event VotingRewardSettled(uint256 reportId, uint256 totalRewardToVoters);

    // ---------------------------------------------------------------------------------------- //
    // *************************************** Errors ***************************************** //
    // ---------------------------------------------------------------------------------------- //

    error IncidentReport__WrongStatus();
    error IncidentReport__WrongPeriod();
    error IncidentReport__WrongChoice();
    error IncidentReport__ChooseBothSides();
    error IncidentReport__NotEnoughVeDEG();
    error IncidentReport__AlreadySettled();
    error IncidentReport__NotSettled();
    error IncidentReport__NotWrongChoice();
    error IncidentReport__AlreadyClaimed();
    error IncidentReport__PoolNotExist();
    error IncidentReport__AlreadyReported();
    error IncidentReport__ZeroAmount();
    error IncidentReport__NoReward();
    error IncidentReport__PayoutExceedCovered();
    error IncidentReport__AlreadyPaid();
    error IncidentReport__OnlyExecutor();
    error IncidentReport__QuorumRatioTooBig();
}

