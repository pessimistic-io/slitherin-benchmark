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

import "./OnboardProposalParameters.sol";
import "./OnboardProposalDependencies.sol";
import "./OnboardProposalEventError.sol";

import "./ExternalTokenDependencies.sol";

/**
 * @notice Onboard Proposal
 */
contract OnboardProposal is
    OnboardProposalParameters,
    OnboardProposalEventError,
    OwnableWithoutContextUpgradeable,
    ExternalTokenDependencies,
    OnboardProposalDependencies
{
    // ---------------------------------------------------------------------------------------- //
    // ************************************* Variables **************************************** //
    // ---------------------------------------------------------------------------------------- //

    // Total number of reports
    uint256 public proposalCounter;

    // Proposal quorum ratio
    uint256 public quorumRatio;

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
    // Proposal ID => Proposal
    mapping(uint256 => Proposal) public proposals;

    // Protocol token => Whether proposed
    // A protocol can only have one pool
    mapping(address => bool) public proposed;

    struct UserVote {
        uint256 choice; // 1: vote for, 2: vote against
        uint256 amount; // veDEG amount for voting
        bool claimed; // Voting reward already claimed
    }
    // User address => report id => user's voting info
    mapping(address => mapping(uint256 => UserVote)) public votes;

    // ---------------------------------------------------------------------------------------- //
    // ************************************* Constructor ************************************** //
    // ---------------------------------------------------------------------------------------- //

    function initialize(
        address _deg,
        address _veDeg
    ) public initializer {
        __Ownable_init();
        __ExternalToken__Init(_deg, _veDeg);

        // Initial quorum 30%
        quorumRatio = 30;
    }

    // ---------------------------------------------------------------------------------------- //
    // ************************************ View Functions ************************************ //
    // ---------------------------------------------------------------------------------------- //

    function getProposal(uint256 _proposalId)
        external
        view
        returns (Proposal memory)
    {
        return proposals[_proposalId];
    }

    function getUserProposalVote(address _user, uint256 _proposalId)
        external
        view
        returns (UserVote memory)
    {
        return votes[_user][_proposalId];
    }

    function getAllProposals()
        external
        view
        returns (Proposal[] memory allProposals)
    {
        uint256 totalProposal = proposalCounter;

        allProposals = new Proposal[](totalProposal);

        for (uint256 i; i < totalProposal; ) {
            allProposals[i] = proposals[i + 1];

            unchecked {
                ++i;
            }
        }
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

    function setQuorumRatio(uint256 _quorumRatio) external onlyOwner {
        quorumRatio = _quorumRatio;
    }

    // ---------------------------------------------------------------------------------------- //
    // ************************************ Main Functions ************************************ //
    // ---------------------------------------------------------------------------------------- //

    /**
     * @notice Start a new proposal
     *
     * @param _name             New project name
     * @param _token            Native token address
     * @param _maxCapacity      Max capacity ratio for the project pool
     * @param _basePremiumRatio Base annual ratio of the premium
     */
    function propose(
        string calldata _name,
        address _token,
        uint256 _maxCapacity,
        uint256 _basePremiumRatio // 10000 == 100% premium annual cost
    ) external onlyOwner {
        _propose(_name, _token, _maxCapacity, _basePremiumRatio, msg.sender);
    }

    /**
     * @notice Start the voting process
     *         Need the approval of dev team (onlyOwner)
     *
     * @param _id Proposal id to start voting
     */
    function startVoting(uint256 _id) external onlyOwner {
        Proposal storage proposal = proposals[_id];

        if (proposal.status != PENDING_STATUS)
            revert OnboardProposal__WrongStatus();

        proposal.status = VOTING_STATUS;
        proposal.voteTimestamp = block.timestamp;

        emit ProposalVotingStart(_id, block.timestamp);
    }

    /**
     * @notice Close a pending proposal
     *         Need the approval of dev team (onlyOwner)
     *
     * @param _id Proposal id
     */
    function closeProposal(uint256 _id) external onlyOwner {
        Proposal storage proposal = proposals[_id];

        // require current proposal to be settled
        if (proposal.status != PENDING_STATUS)
            revert OnboardProposal__WrongStatus();

        proposal.status = CLOSE_STATUS;

        proposed[proposal.protocolToken] = false;

        emit ProposalClosed(_id, block.timestamp);
    }

    /**
     * @notice Vote for a proposal
     *
     *         Voting power is decided by the (unlocked) balance of veDEG
     *         Once voted, those veDEG will be locked
     *
     * @param _id     Proposal id
     * @param _isFor  Voting choice
     * @param _amount Amount of veDEG to vote
     */
    function vote(
        uint256 _id,
        uint256 _isFor,
        uint256 _amount
    ) external {
        _vote(_id, _isFor, _amount, msg.sender);
    }

    /**
     * @notice Settle the proposal result
     *
     * @param _id Proposal id
     */
    function settle(uint256 _id) external {
        Proposal storage proposal = proposals[_id];

        if (proposal.status != VOTING_STATUS)
            revert OnboardProposal__WrongStatus();

        if (!_passedVotingPeriod(proposal.voteTimestamp))
            revert OnboardProposal__WrongPeriod();

        // If reached quorum, settle the result
        if (_checkQuorum(proposal.numFor + proposal.numAgainst)) {
            uint256 res = _getVotingResult(
                proposal.numFor,
                proposal.numAgainst
            );

            // If this proposal not passed, allow new proposals for the same project
            // If it passed, not allow the same proposals
            if (res != PASS_RESULT) {
                // Allow for new proposals to be proposed for this protocol
                proposed[proposal.protocolToken] = false;
            }

            proposal.result = res;
            proposal.status = SETTLED_STATUS;

            emit ProposalSettled(_id, res);
        }
        // Else, set the result as "FAILED"
        else {
            proposal.result = FAILED_RESULT;
            proposal.status = SETTLED_STATUS;

            // Allow for new proposals to be proposed for this protocol
            proposed[proposal.protocolToken] = false;

            emit ProposalFailed(_id);
        }
    }

    /**
     * @notice Claim back veDEG after voting result settled
     *
     * @param _id Proposal id
     */
    function claim(uint256 _id) external {
        _claim(_id, msg.sender);
    }

    // ---------------------------------------------------------------------------------------- //
    // *********************************** Internal Functions ********************************* //
    // ---------------------------------------------------------------------------------------- //

    /**
     * @notice Start a new proposal
     *
     * @param _name             New project name
     * @param _token            Native token address
     * @param _maxCapacity      Max capacity ratio for the project pool
     * @param _basePremiumRatio Base annual ratio of the premium
     */
    function _propose(
        string calldata _name,
        address _token,
        uint256 _maxCapacity,
        uint256 _basePremiumRatio, // 10000 == 100% premium annual cost
        address _user
    ) internal {
        if (priorityPoolFactory.tokenRegistered(_token))
            revert OnboardProposal__AlreadyProtected();

        if (_maxCapacity == 0 || _maxCapacity > MAX_CAPACITY_RATIO)
            revert OnboardProposal__WrongCapacity();

        if (_basePremiumRatio >= 10000 || _basePremiumRatio == 0)
            revert OnboardProposal__WrongPremium();

        if (proposed[_token]) revert OnboardProposal__AlreadyProposed();

        // Burn degis tokens to start a proposal
        // deg.burnDegis(_user, PROPOSE_THRESHOLD);

        proposed[_token] = true;

        uint256 currentCounter = ++proposalCounter;
        // Record the proposal info
        Proposal storage proposal = proposals[currentCounter];
        proposal.name = _name;
        proposal.protocolToken = _token;
        proposal.proposer = _user;
        proposal.proposeTimestamp = block.timestamp;
        proposal.status = PENDING_STATUS;
        proposal.maxCapacity = _maxCapacity;
        proposal.basePremiumRatio = _basePremiumRatio;

        emit NewProposal(_name, _token, _user, _maxCapacity, _basePremiumRatio);
    }

    /**
     * @notice Vote for a proposal
     *
     * @param _id     Proposal id
     * @param _isFor  Voting choice
     * @param _amount Amount of veDEG to vote
     */
    function _vote(
        uint256 _id,
        uint256 _isFor,
        uint256 _amount,
        address _user
    ) internal {
        Proposal storage proposal = proposals[_id];

        // Should be manually switched on the voting process
        if (proposal.status != VOTING_STATUS)
            revert OnboardProposal__WrongStatus();
        if (_isFor != 1 && _isFor != 2) revert OnboardProposal__WrongChoice();
        if (_passedVotingPeriod(proposal.voteTimestamp))
            revert OnboardProposal__WrongPeriod();
        if (_amount == 0) revert OnboardProposal__ZeroAmount();

        _enoughVeDEG(_user, _amount);

        // Lock vedeg until this report is settled
        veDeg.lockVeDEG(_user, _amount);

        // Record the user's choice
        UserVote storage userVote = votes[_user][_id];
        if (userVote.amount > 0) {
            if (userVote.choice != _isFor)
                revert OnboardProposal__ChooseBothSides();
        } else {
            userVote.choice = _isFor;
        }
        userVote.amount += _amount;

        // Record the vote for this report
        if (_isFor == 1) {
            proposal.numFor += _amount;
        } else {
            proposal.numAgainst += _amount;
        }

        emit ProposalVoted(_id, _user, _isFor, _amount);
    }

    /**
     * @notice Claim back veDEG after voting result settled
     *
     * @param _id Proposal id
     */
    function _claim(uint256 _id, address _user) internal {
        Proposal storage proposal = proposals[_id];

        if (proposal.status != SETTLED_STATUS)
            revert OnboardProposal__WrongStatus();

        UserVote storage userVote = votes[_user][_id];

        // @audit Add claimed check
        if (userVote.claimed) revert OnboardProposal__AlreadyClaimed();

        // Unlock the veDEG used for voting
        // No reward / punishment
        veDeg.unlockVeDEG(_user, userVote.amount);

        userVote.claimed = true;

        emit Claimed(_id, _user, userVote.amount);
    }

    /**
     * @notice Get the final voting result
     *
     * @param _numFor     Votes for
     * @param _numAgainst Votes against
     *
     * @return result Pass, reject or tied
     */
    function _getVotingResult(uint256 _numFor, uint256 _numAgainst)
        internal
        pure
        returns (uint256 result)
    {
        if (_numFor > _numAgainst) result = PASS_RESULT;
        else if (_numFor < _numAgainst) result = REJECT_RESULT;
        else result = TIED_RESULT;
    }

    /**
     * @notice Check whether has passed the voting time period
     *
     * @param _voteTimestamp Start timestamp of the voting
     *
     * @return hasPassed True for passing
     */
    function _passedVotingPeriod(uint256 _voteTimestamp)
        internal
        view
        returns (bool)
    {
        uint256 endTime = _voteTimestamp + PROPOSAL_VOTING_PERIOD;
        return block.timestamp > endTime;
    }

    /**
     * @notice Check quorum requirement
     *         30% of totalSupply is the minimum requirement for participation
     *
     * @param _totalVotes Total vote numbers
     */
    function _checkQuorum(uint256 _totalVotes) internal view returns (bool) {
        return _totalVotes >= (veDeg.totalSupply() * quorumRatio) / 100;
    }

    /**
     * @notice Check veDEG to be enough
     *         Only unlocked veDEG will be counted
     *
     * @param _user   User address
     * @param _amount Amount to fulfill
     */
    function _enoughVeDEG(address _user, uint256 _amount) internal view {
        uint256 unlockedBalance = veDeg.balanceOf(_user) - veDeg.locked(_user);
        if (unlockedBalance < _amount) revert OnboardProposal__NotEnoughVeDEG();
    }
}

