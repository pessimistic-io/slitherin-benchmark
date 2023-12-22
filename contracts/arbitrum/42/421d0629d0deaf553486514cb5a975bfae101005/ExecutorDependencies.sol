// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.13;

// import "../../interfaces/IPriorityPool.sol";
import "./IPriorityPoolFactory.sol";
import "./IOnboardProposal.sol";

import "./ITreasury.sol";

interface IPriorityPool {
    function liquidatePool(uint256 amount) external;
}

interface IIncidentReport {
    struct Report {
        uint256 poolId; // Project pool id
        uint256 reportTimestamp; // Time of starting report
        address reporter; // Reporter address
        uint256 voteTimestamp; // Voting start timestamp
        uint256 numFor; // Votes voting for
        uint256 numAgainst; // Votes voting against
        uint256 round; // 0: Initial round 3 days, 1: Extended round 1 day, 2: Double extended 1 day
        uint256 status; // 0: INIT, 1: PENDING, 2: VOTING, 3: SETTLED, 404: CLOSED
        uint256 result; // 1: Pass, 2: Reject, 3: Tied
        uint256 votingReward; // Voting reward per veDEG
        uint256 payout; // Payout amount of this report (partial payout)
    }

    function getReport(uint256) external view returns (Report memory);

    function executed(uint256 _reportId) external;
}

abstract contract ExecutorDependencies {
    IPriorityPoolFactory public priorityPoolFactory;
    IIncidentReport public incidentReport;
    IOnboardProposal public onboardProposal;
    ITreasury public treasury;
}

