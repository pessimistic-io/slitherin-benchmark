// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.13;

interface IOnboardProposal {
    struct Proposal {
        string name; // Pool name ("JOE", "GMX")
        address protocolToken; // Protocol native token address
        address proposer; // Proposer address
        uint256 proposeTimestamp; // Timestamp when proposing
        uint256 voteTimestamp; // Timestamp when start voting
        uint256 numFor; // Votes voting for
        uint256 numAgainst; // Votes voting against
        uint256 maxCapacity; // Max capacity ratio
        uint256 basePremiumRatio; // Base annual premium ratio
        uint256 poolId; // Priority pool id
        uint256 status; // Current status (PENDING, VOTING, SETTLED, CLOSED)
        uint256 result; // Final result (PASSED, REJECTED, TIED)
    }

    struct UserVote {
        uint256 choice; // 1: vote for, 2: vote against
        uint256 amount; // veDEG amount for voting
        bool claimed; // Voting reward already claimed
    }

    event NewProposal(
        string name,
        address token,
        uint256 maxCapacity,
        uint256 priceRatio
    );
    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );
    event ProposalSettled(uint256 proposalId, uint256 result);
    event ProposalVoted(
        uint256 proposalId,
        address indexed user,
        uint256 voteFor,
        uint256 amount
    );

    function claim(uint256 _proposalId, address _user) external;

    function closeProposal(uint256 _proposalId) external;

    function deg() external view returns (address);

    function executor() external view returns (address);

    function getProposal(uint256 _proposalId)
        external
        view
        returns (Proposal memory);

    function incidentReport() external view returns (address);

    function priorityPoolFactory() external view returns (address);

    function onboardProposal() external view returns (address);

    function owner() external view returns (address);

    function policyCenter() external view returns (address);

    function poolProposed(address) external view returns (bool);

    function proposalCounter() external view returns (uint256);

    function proposals(uint256)
        external
        view
        returns (
            string memory name,
            address protocolToken,
            address proposer,
            uint256 proposeTimestamp,
            uint256 numFor,
            uint256 numAgainst,
            uint256 maxCapacity,
            uint256 priceRatio,
            uint256 poolId,
            uint256 status,
            uint256 result
        );

    function propose(
        string memory _name,
        address _token,
        uint256 _maxCapacity,
        uint256 _priceRatio,
        address _user
    ) external;

    function protectionPool() external view returns (address);

    function renounceOwnership() external;

    function setExecutor(address _executor) external;

    function setIncidentReport(address _incidentReport) external;

    function setPriorityPoolFactory(address _priorityPoolFactory) external;

    function setOnboardProposal(address _onboardProposal) external;

    function setPolicyCenter(address _policyCenter) external;

    function setProtectionPool(address _protectionPool) external;

    function settle(uint256 _proposalId) external;

    function startVoting(uint256 _proposalId) external;

    function transferOwnership(address newOwner) external;

    function getUserProposalVote(address user, uint256 proposalId)
        external
        view
        returns (UserVote memory);

    function veDeg() external view returns (address);

    function vote(
        uint256 _reportId,
        uint256 _isFor,
        uint256 _amount,
        address _user
    ) external;
}

