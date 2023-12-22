// SPDX-License-Identifier: GPL-3.0-or-later

/*
 //======================================================================\\
 //======================================================================\\
  *******         **********     ***********     *****     ***********
  *      *        *              *                 *       *
  *        *      *              *                 *       *
  *         *     *              *                 *       *
  *         *     *              *                 *       *
  *         *     **********     *       *****     *       ***********
  *         *     *              *         *       *                 *
  *         *     *              *         *       *                 *
  *        *      *              *         *       *                 *
  *      *        *              *         *       *                 *
  *******         **********     ***********     *****     ***********
 \\======================================================================//
 \\======================================================================//
*/

pragma solidity ^0.8.13;

import "./OwnableWithoutContextUpgradeable.sol";
import "./ExecutorDependencies.sol";
import "./VotingParameters.sol";
import "./ExecutorEventError.sol";

/**
 * @title Executor Contract
 *
 * @author Eric Lee (ericlee@375labs.org) & Primata (primata@375labs.org)
 *
 * @notice This is the executor contract for degis Protocol Protection
 * 
 *         The executor is responsible for the execution of the reports and pool proposals
 *         Both administrators or users can execute proposals and reports
 * 
 *         Execute a report means:
 *             - Mark the report as executed
 *             - Reward the reported from the Treasury
 *             - Liquidate / Move the total payout amount out of the priority pool (to the payout pool) 
 * 
 *         Execute a proposal means:
 *             - Mark the proposal as executed
 *             - Create a new priority pool
 */
contract Executor is
    VotingParameters,
    ExecutorEventError,
    OwnableWithoutContextUpgradeable,
    ExecutorDependencies
{
    // ---------------------------------------------------------------------------------------- //
    // ************************************* Variables **************************************** //
    // ---------------------------------------------------------------------------------------- //

    // Whether report already executed
    mapping(uint256 => bool) public reportExecuted;

    // Whether proposal already executed
    mapping(uint256 => bool) public proposalExecuted;

    // ---------------------------------------------------------------------------------------- //
    // ************************************* Constructor ************************************** //
    // ---------------------------------------------------------------------------------------- //

    function initialize() public initializer {
        __Ownable_init();
    }

    // ---------------------------------------------------------------------------------------- //
    // ************************************ Set Functions ************************************* //
    // ---------------------------------------------------------------------------------------- //

    function setPriorityPoolFactory(address _priorityPoolFactory)
        external
        onlyOwner
    {
        priorityPoolFactory = IPriorityPoolFactory(_priorityPoolFactory);
    }

    function setIncidentReport(address _incidentReport) external onlyOwner {
        incidentReport = IIncidentReport(_incidentReport);
    }

    function setOnboardProposal(address _onboardProposal) external onlyOwner {
        onboardProposal = IOnboardProposal(_onboardProposal);
    }

    function setTreasury(address _treasury) external onlyOwner {
        treasury = ITreasury(_treasury);
    }

    // ---------------------------------------------------------------------------------------- //
    // ************************************ Main Functions ************************************ //
    // ---------------------------------------------------------------------------------------- //

    /**
     * @notice Execute a report
     *         The report must already been settled and the result is PASSED
     *         Execution means:
     *             1) Give 10% of protocol income to reporter (USDC)
     *             2) Move the total payout amount out of the priority pool (to payout pool)
     *             3) Deploy new generations of CRTokens and PRI-LP tokens
     *
     *         Can not execute a report before the previous liquidation ended
     *
     * @param _reportId Id of the report to be executed
     */
    function executeReport(uint256 _reportId) public {
        // Check and mark the report as "executed"
        if (reportExecuted[_reportId]) revert Executor__AlreadyExecuted();
        reportExecuted[_reportId] = true;

        IIncidentReport.Report memory report = incidentReport.getReport(
            _reportId
        );

        if (report.status != SETTLED_STATUS)
            revert Executor__ReportNotSettled();
        if (report.result != PASS_RESULT) revert Executor__ReportNotPassed();

        // Executed callback function
        incidentReport.executed(_reportId);

        // Give 10% of treasury to the reporter
        treasury.rewardReporter(report.poolId, report.reporter);

        // Unpause the priority pool and protection pool
        // factory.pausePriorityPool(report.poolId, false);

        // Liquidate the pool
        (, address poolAddress, , , ) = priorityPoolFactory.pools(
            report.poolId
        );
        IPriorityPool(poolAddress).liquidatePool(report.payout);

        emit ReportExecuted(poolAddress, report.poolId, _reportId);
    }

    /**
     * @notice Execute the proposal
     *         The proposal must already been settled and the result is PASSED
     *         New priority pool will be deployed with parameters
     *
     * @param _proposalId Proposal id
     */
    function executeProposal(uint256 _proposalId)
        external
        returns (address newPriorityPool)
    {
        // Check and mark the proposal as "executed"
        if (proposalExecuted[_proposalId]) revert Executor__AlreadyExecuted();
        proposalExecuted[_proposalId] = true;

        IOnboardProposal.Proposal memory proposal = onboardProposal.getProposal(
            _proposalId
        );

        if (proposal.status != SETTLED_STATUS)
            revert Executor__ProposalNotSettled();
        if (proposal.result != PASS_RESULT)
            revert Executor__ProposalNotPassed();

        // Execute the proposal
        newPriorityPool = priorityPoolFactory.deployPool(
            proposal.name,
            proposal.protocolToken,
            proposal.maxCapacity,
            proposal.basePremiumRatio
        );

        emit NewPoolExecuted(
            newPriorityPool,
            _proposalId,
            proposal.protocolToken
        );
    }
}

