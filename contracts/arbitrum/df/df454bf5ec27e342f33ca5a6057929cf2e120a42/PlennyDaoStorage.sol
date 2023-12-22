// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

import "./PlennyDappFactory.sol";

contract PlennyDaoStorage {

    /// The name of this contract
    string public constant NAME = "PlennyDao";

    // The initial delay when creating a proposal, in blocks
    uint public votingDelay;
    // The duration of voting on a proposal, in blocks
    uint public votingDuration;
    // The quorum vote % needed for each proposal  / BASE
    uint public minQuorum;
    // The % of votes required in order for a voter to become a proposer / BASE
    uint public proposalThreshold;

    /// The EIP-712 typehash for the contract's domain
    bytes32 public constant DOMAIN_TYPEHASH = keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");

    /// The EIP-712 typehash for the ballot struct used by the contract
    bytes32 public constant BALLOT_TYPEHASH = keccak256("Ballot(uint256 _proposalID,bool support)");

    mapping (bytes32 => bool) public queuedTransactions;

    uint public constant GRACE_PERIOD = 93046;   // blocks count, 14 days approximately
    uint public constant MINIMUM_DELAY = 10;     // blocks count, 2 minutes approximately
    uint public constant MAXIMUM_DELAY = 199384; // blocks count, 30 days approximately
    uint64 public delay;

    address public guardian;

    uint public constant BASE = 10000;

    uint public proposalCount;
    struct Proposal {
        uint id;
        address proposer;
        uint eta;
        address[] targets;
        uint[] values;
        string[] signatures;
        bytes[] calldatas;
        uint startBlock;
        uint startBlockAlt;
        uint endBlock;
        uint forVotes;
        uint againstVotes;
        bool canceled;
        bool executed;
        mapping (address => Receipt) receipts;
    }

    struct Receipt {
        bool hasVoted;
        bool support;
        uint votes;
    }

    enum ProposalState {
        Pending,
        Active,
        Canceled,
        Defeated,
        Succeeded,
        Queued,
        Expired,
        Executed
    }

    mapping (uint => Proposal) public proposals;
    mapping (address => uint) public latestProposalIds;
}

