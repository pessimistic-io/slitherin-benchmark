// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

// The Governance Policy submits & activates instructions in a INSTR module

import {Owned} from "./Owned.sol";
import {Instructions} from "./INSTR.sol";
import {StakedBarnBridgeToken} from "./XBOND.sol";
import "./Kernel.sol";

error NotAuthorized();
error UnableToActivate();
error ProposalAlreadyActivated();
error ProposalTimelockNotComplete();

error WarmupNotCompleted();
error UserAlreadyVoted();
error ProposalIsNotActive();
error DepositedAfterActivation();
error PastVotingPeriod();


error ExecutorNotSubmitter();
error NotEnoughVotesToExecute();
error ProposalAlreadyExecuted();
error ExecutionTimelockStillActive();
error ExecutionWindowExpired(); 
error UnmetCollateralDuration();
error CollateralAlreadyReturned();
error CancelledProposal();

struct ProposalMetadata {
    address submitter;
    uint256 submissionTimestamp;
    uint256 collateralAmt;
    uint256 activationTimestamp;
    uint256 totalRegisteredVotes;
    uint256 yesVotes;
    uint256 noVotes;
    bool isExecuted;
    bool isCollateralReturned;
    bool isCancelled;
    mapping(address => uint256) votesCastByUser;
}

/// @notice BarnBridgeGovernance
/// @dev The BarnGovernancePolicy is also the Kernel's Executor.
contract BarnGovernancePolicy is Policy, Owned {
    /////////////////////////////////////////////////////////////////////////////////
    //                         Kernel Policy Configuration                         //
    /////////////////////////////////////////////////////////////////////////////////

    Instructions public INSTR;
    StakedBarnBridgeToken public XBOND;

    constructor(Kernel _kernel, address _dao) Policy(_kernel) Owned(_dao) {
        DEPLOYMENT_TIMESTAMP = block.timestamp;
    }

    function configureDependencies() external override returns (bytes5[] memory dependencies) {
        dependencies = new bytes5[](2);
        dependencies[0] = bytes5("INSTR");
        dependencies[1] = bytes5("XBOND");

        INSTR = Instructions(getModuleAddress(dependencies[0]));
        XBOND = StakedBarnBridgeToken(getModuleAddress(dependencies[1]));
    }

    function requestPermissions()
        external
        view
        override
        onlyKernel
        returns (Permissions[] memory requests)
    {
        requests = new Permissions[](4);
        requests[0] = Permissions("INSTR", INSTR.store.selector);
        requests[1] = Permissions("XBOND", XBOND.resetActionTimestamp.selector);
        requests[2] = Permissions("XBOND", XBOND.transferFrom.selector);
        requests[3] = Permissions("XBOND", XBOND.transfer.selector);
    }

    /////////////////////////////////////////////////////////////////////////////////
    //                             Policy Variables                                //
    /////////////////////////////////////////////////////////////////////////////////


    event ProposalSubmitted(uint256 proposalId, string title, string proposalURI);
    event ProposalActivated(uint256 proposalId, uint256 timestamp);
    event VotesCast(uint256 proposalId, address voter, bool approve, uint256 userVotes);
    event ProposalExecuted(uint256 proposalId);
    event CollateralReclaimed(uint256 proposalId, uint256 tokensReclaimed_);
    event ProposalCancelled(uint256 proposalId);


    /// @notice Return a proposal metadata object for a given proposal id.
    mapping(uint256 => ProposalMetadata) public getProposalMetadata;

    /// @notice stores total collateral across all proposals per user
    /// @dev    user => totalCollateral
    mapping (address => uint256) public getTotalCollateralForUser;

    /// @notice The amount of XBOND a proposer needs to post in collateral in order to submit a proposal
    /// @dev    This number is expressed as a percentage of total supply in basis points: 500 = 5% of the supply
    uint256 public constant COLLATERAL_REQUIREMENT = 150;

    /// @notice The minimum amount of XBOND the proposer must post in collateral to submit
    uint256 public constant COLLATERAL_MINIMUM = 5_000e18;

    /// @notice Amount of time a wallet must wait after depositing before they can vote.
    uint256 public constant WARMUP_PERIOD = 2 days;

    /// @notice Amount of time a submitted proposal must exist before triggering activation.
    uint256 public constant ACTIVATION_TIMELOCK = 2 days;

    /// @notice Amount of time a submitted proposal must exist before triggering activation.
    uint256 public constant ACTIVATION_DEADLINE = 3 days;

    /// @notice Net votes required to execute a proposal on chain as a percentage of total registered votes.
    uint256 public constant EXECUTION_THRESHOLD = 33;

    /// @notice The period of time a proposal has for voting
    uint256 public constant VOTING_PERIOD = 3 days;

    /// @notice Required time for a proposal before it can be activated.
    /// @dev    This amount should be greater than 0 to prevent flash loan attacks.
    uint256 public constant EXECUTION_TIMELOCK = VOTING_PERIOD + 2 days;

    /// @notice Amount of time after the proposal is activated (NOT AFTER PASSED) when it can be activated (otherwise proposal will go stale).
    /// @dev    This is inclusive of the voting period (so the deadline is really ~4 days, assuming a 3 day voting window).
    uint256 public constant EXECUTION_DEADLINE = 2 weeks;

    /// @notice Amount of time a non-executed proposal must wait for the proposal to go through.
    /// @dev    This is inclusive of the voting period (so the deadline is really ~4 days, assuming a 3 day voting window).
    uint256 public constant COLLATERAL_DURATION = 16 weeks;

    /// @notice Amount of time after deployment to prevent proposals from being submitted.
    /// @dev    This timelock is used to allow a healthy level of XBOND to build up before voting.
    uint256 public constant PROPOSAL_TIMELOCK = 1 weeks;

    /// @notice timestamp that the contract was deployed at
    uint256 public immutable DEPLOYMENT_TIMESTAMP;

    /////////////////////////////////////////////////////////////////////////////////
    //                               User Actions                                  //
    /////////////////////////////////////////////////////////////////////////////////

    function _max(uint256 a, uint256 b) public pure returns (uint256) {
        return a > b ? a : b;
    }

    function submitProposal(
        Instruction[] calldata _instructions,
        string calldata _title,
        string calldata _proposalURI
    ) external {
        if (block.timestamp < DEPLOYMENT_TIMESTAMP + PROPOSAL_TIMELOCK) {
            revert ProposalTimelockNotComplete();
        }

        if (XBOND.lastDepositTimestamp(msg.sender) + WARMUP_PERIOD > block.timestamp) {
            revert WarmupNotCompleted();
        }

        // transfer 1.5% of the total vote supply in XBOND (min 5k XBOND)
        uint256 collateral = _max(XBOND.totalSupply() * COLLATERAL_REQUIREMENT / 10_000, COLLATERAL_MINIMUM);
        getTotalCollateralForUser[msg.sender] += collateral;
        XBOND.transferFrom(msg.sender, address(this), collateral);

        uint256 proposalId = INSTR.store(_instructions);
        ProposalMetadata storage proposal = getProposalMetadata[proposalId];

        proposal.submitter = msg.sender;
        proposal.collateralAmt = collateral;
        proposal.submissionTimestamp = block.timestamp;

        XBOND.resetActionTimestamp(msg.sender);

        emit ProposalSubmitted(proposalId, _title, _proposalURI);
    }

    function activateProposal(uint256 proposalId_) external {
        ProposalMetadata storage proposal = getProposalMetadata[proposalId_];

        if (msg.sender != proposal.submitter) {
            revert NotAuthorized();
        }

        if (block.timestamp < proposal.submissionTimestamp + ACTIVATION_TIMELOCK || 
            block.timestamp > proposal.submissionTimestamp + ACTIVATION_DEADLINE) {
            revert UnableToActivate();
        }

        if (proposal.activationTimestamp != 0) {
            revert ProposalAlreadyActivated();
        }

        proposal.activationTimestamp = block.timestamp;
        proposal.totalRegisteredVotes = XBOND.totalSupply();

        XBOND.resetActionTimestamp(msg.sender);

        emit ProposalActivated(proposalId_, block.timestamp);
    }

    function vote(uint256 _proposalId, bool _approve) external {
        ProposalMetadata storage proposal = getProposalMetadata[_proposalId];
        uint256 userVotes = XBOND.balanceOf(msg.sender) + getTotalCollateralForUser[msg.sender];

        if (proposal.activationTimestamp == 0) {
            revert ProposalIsNotActive();
        }

        if (XBOND.lastDepositTimestamp(msg.sender) + WARMUP_PERIOD > block.timestamp) {
            revert WarmupNotCompleted();
        }

        if (XBOND.lastDepositTimestamp(msg.sender) > proposal.activationTimestamp) { 
            revert DepositedAfterActivation();
        }

        if (proposal.votesCastByUser[msg.sender] > 0) {
            revert UserAlreadyVoted();
        }

        if (block.timestamp > proposal.activationTimestamp + VOTING_PERIOD) {
            revert PastVotingPeriod();
        }

        if (_approve) {
            proposal.yesVotes += userVotes;
        } else {
            proposal.noVotes += userVotes;
        }

        proposal.votesCastByUser[msg.sender] = userVotes;
        XBOND.resetActionTimestamp(msg.sender);

        emit VotesCast(_proposalId, msg.sender, _approve, userVotes);
    }

    function executeProposal(uint256 _proposalId) external {
        ProposalMetadata storage proposal = getProposalMetadata[_proposalId];

        if (msg.sender != proposal.submitter) { 
            revert ExecutorNotSubmitter(); 
        }

        if ((proposal.yesVotes - proposal.noVotes) * 100 < proposal.totalRegisteredVotes * EXECUTION_THRESHOLD) {
            revert NotEnoughVotesToExecute();
        }

        if (proposal.isExecuted) {
            revert ProposalAlreadyExecuted();
        }

        /// @dev    2 days after the voting period ends
        if (block.timestamp < proposal.activationTimestamp + EXECUTION_TIMELOCK) {
            revert ExecutionTimelockStillActive();
        }

        /// @dev    7 days after the proposal is SUBMITTED
        if (block.timestamp > proposal.activationTimestamp + EXECUTION_DEADLINE) {
            revert ExecutionWindowExpired();
        }

        if (proposal.isCancelled) {
            revert CancelledProposal();
        }

        Instruction[] memory instructions = INSTR.getInstructions(_proposalId);
        uint256 totalInstructions = instructions.length;

        for (uint256 step; step < totalInstructions; ) {
            kernel.executeAction(instructions[step].action, instructions[step].target);
            unchecked { 
                ++step;
            }
        }

        proposal.isExecuted = true;

        XBOND.resetActionTimestamp(msg.sender);

        emit ProposalExecuted(_proposalId);
    }

    function reclaimCollateral(uint256 _proposalId) external {
        ProposalMetadata storage proposal = getProposalMetadata[_proposalId];

        if (block.timestamp < proposal.submissionTimestamp + COLLATERAL_DURATION ) { 
            revert UnmetCollateralDuration();
        }

        if (proposal.isCollateralReturned) {
            revert CollateralAlreadyReturned();
        }

        if (msg.sender != proposal.submitter) {
            revert NotAuthorized();
        }

        proposal.isCollateralReturned = true;
        getTotalCollateralForUser[msg.sender] -= proposal.collateralAmt;
        XBOND.transfer(proposal.submitter, proposal.collateralAmt);

        emit CollateralReclaimed(_proposalId, proposal.collateralAmt);
    }

    function emergencyCancelProposal(uint256 _proposalId) external onlyOwner {
        getProposalMetadata[_proposalId].isCancelled = true;
        emit ProposalCancelled(_proposalId);
    }
}
