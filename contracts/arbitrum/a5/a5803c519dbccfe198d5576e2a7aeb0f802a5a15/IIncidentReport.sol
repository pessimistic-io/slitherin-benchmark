// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.13;

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

    struct TempResult {
        uint256 a;
        uint256 b;
        bool c;
    }
    struct UserVote {
        uint256 choice;
        uint256 amount;
        bool claimed;
    }

    /**
     * @notice Cool down period when you submit a wrong report
     *         Wrong Report: Closed by the Admin team
     *
     * @return COOLDOWN_WRONG_REPORT Cooldown time in second (before you can submit another report)
     */
    function COOLDOWN_WRONG_REPORT() external view returns (uint256);

    /**
     * @notice Claim reward
     *         Users can claim reward when they vote correctly
     *
     * @param _reportId Report id
     */
    function claimReward(uint256 _reportId) external;

    /**
     * @notice Close a report
     *         Only callable by the owner
     *
     * @param _reportId Report id
     */
    function closeReport(uint256 _reportId) external;

    function deg() external view returns (address);

    function executor() external view returns (address);

    function getReport(uint256 _id) external view returns (Report memory);

    function getTempResult(uint256 _id)
        external
        view
        returns (TempResult memory);

    function getUserVote(address _user, uint256 _id)
        external
        view
        returns (UserVote memory);

    function incidentReport() external view returns (address);

    function priorityPoolFactory() external view returns (address);

    function onboardProposal() external view returns (address);

    function owner() external view returns (address);

    function payDebt(uint256 _reportId, address _user) external;

    function policyCenter() external view returns (address);

    function poolReported(address) external view returns (bool);

    function protectionPool() external view returns (address);

    function renounceOwnership() external;

    function report(
        uint256 _poolId,
        uint256 _payout,
        address _user
    ) external;

    function reportCounter() external view returns (uint256);

    function reportTempResults(uint256)
        external
        view
        returns (
            uint256 result,
            uint256 sampleTimestamp,
            bool hasChanged
        );

    function reports(uint256)
        external
        view
        returns (
            uint256 poolId,
            uint256 reportTimestamp,
            address reporter,
            uint256 voteTimestamp,
            uint256 numFor,
            uint256 numAgainst,
            uint256 round,
            uint256 status,
            uint256 result,
            uint256 votingReward,
            uint256 payout
        );

    function setExecutor(address _executor) external;

    function setIncidentReport(address _incidentReport) external;

    function setPriorityPoolFactory(address _priorityPoolFactory) external;

    function setOnboardProposal(address _onboardProposal) external;

    function setPolicyCenter(address _policyCenter) external;

    function setProtectionPool(address _protectionPool) external;

    function settle(uint256 _reportId) external;

    function startVoting(uint256 _reportId) external;

    function transferOwnership(address newOwner) external;

    function unpausePools(uint256 _poolId) external;

    function userCoolDownUntil(address) external view returns (uint256);

    function votes(address, uint256)
        external
        view
        returns (
            uint256 choice,
            uint256 amount,
            bool claimed
        );

    function veDeg() external view returns (address);

    function vote(
        uint256 _reportId,
        uint256 _isFor,
        uint256 _amount,
        address _user
    ) external;

    function poolReports(uint256 _poolId, uint256 _index)
        external
        view
        returns (uint256);

    function getPoolReportsAmount(uint256 _poolId)
        external
        view
        returns (uint256);

    function executed(uint256 _reportId) external;
}

