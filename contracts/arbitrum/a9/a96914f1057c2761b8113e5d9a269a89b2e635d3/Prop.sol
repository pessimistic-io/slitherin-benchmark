// SPDX-License-Identifier: MIT

import "./Idea.sol";
import "./Funding.sol";

pragma solidity ^0.8.11;

enum VoteKind {
	For,
	Against
}

/**
 * Details of individual votes must be stored to allow "undo" functionality.
 */
struct Vote {
	uint256 votes;
	VoteKind kind;
}

/**
 * Represents an ongoing vote to implement a new funding rate for an idea.
 * Votes are weighted based on balances held.
 */
contract Prop {
	/* The idea constituting the voting body */
	Idea public governed;

	/* The idea being funded by the prop */
	address public toFund;

	/* The funding rate being voted on */
	FundingRate internal rate;

	/* Users that voted on the proposal - should receive a refund after */
	mapping (address => Vote) public refunds;

	/* Where metadata about the proposal is stored */
	string public ipfsAddr;
	uint256 public nVoters;

	uint256 public votesFor;
	uint256 public votesAgainst;

	/* The title of the proposal */
	string public title;

	address[] public voters;

	/* The number of seconds that the vote lasts */
	uint256 public expiresAt;

	/* A new proposal was created, the details of which are on IPFS */
	event NewProposal(Prop prop, Idea governed, address toFund, string propIpfsHash, uint256 expiresAt);

	/* A user voted on a new rate for the proposal */
	event VoteCast(address voter, uint256 votes, VoteKind kind);

	modifier isActive {
		require(block.timestamp < expiresAt, "Voting on proposal has closed.");
		_;
	}

	/**
	 * Creates a new proposal, whose details should be on IPFS already, and that
	 * expires at the indicated time.
	 *
	 * @param _propName - The title of the proposal
	 * @param _jurisdiction - The token measuring votes
	 * @param _toFund - The idea whose funding is being voted on
	 * @param _token - The token being used to fund the idea
	 * @param _fundingType - How the reward should be fundraised (i.e., minting or from the treasury)
	 * @param _proposalIpfsHash - The details of the proposal, in any form, available
	 * on IPFS
	 * @param _voteExpiry - The number of seconds that the vote can last for
	 */
	constructor(string memory _propName, Idea _jurisdiction, address _toFund, address _token, FundingType _fundingType, uint256 _fundingAmount, string memory _proposalIpfsHash, uint256 _voteExpiry) {
		title = _propName;
		governed = _jurisdiction;
		toFund = _toFund;
		rate = FundingRate(_token, _fundingAmount, false, _fundingType);
		expiresAt = _voteExpiry;
		ipfsAddr = _proposalIpfsHash;

		emit NewProposal(this, _jurisdiction, _toFund, _proposalIpfsHash, expiresAt);
	}

	/**
	 * Delegates the specified number of votes (tokens) to this proposal with
	 * the given vote details.
	 */
	function vote(uint256 _votes, VoteKind _kind) external isActive {
		require(refunds[msg.sender].votes >= _votes || governed.transferFrom(msg.sender, address(this), _votes - refunds[msg.sender].votes), "Failed to delegate votes");

		// De-register old votes, and add the user as a voter
		if (refunds[msg.sender].votes > 0) {
			if (refunds[msg.sender].votes > _votes) {
				// Replace the user's old vote by returning their tokens
				uint256 diffRefund = refunds[msg.sender].votes - _votes;

				require(governed.transfer(msg.sender, diffRefund), "Failed to refund freed votes");
			}

			if (refunds[msg.sender].kind == VoteKind.For) {
				votesFor -= refunds[msg.sender].votes;
			} else {
				votesAgainst -= refunds[msg.sender].votes;
			}
		} else if (_votes > 0) {
			voters.push(msg.sender);
			nVoters++;
		}

		// Votes have to be weighted by their balance of the governing token
		if (_kind == VoteKind.For) {
			votesFor += _votes;
		} else {
			votesAgainst += _votes;
		}

		refunds[msg.sender] = Vote(_votes, _kind);
		emit VoteCast(msg.sender, _votes, _kind);
	}

	/**
	 * Deallocates all votes from the user.
	 */
	function refundVotes() external isActive {
		require(refunds[msg.sender].votes > 0, "No votes left to refund.");

		uint256 w = refunds[msg.sender].votes;

		// Refund the user
		require(governed.transfer(msg.sender, w), "Failed to refund votes");

		// Subtract their weighted votes from the total
		if (refunds[msg.sender].kind == VoteKind.For) {
			votesFor -= w;
		} else {
			votesAgainst -= w;
		}

		// Remove the user's refund entry
		delete refunds[msg.sender];

		for (uint256 i = 0; i < nVoters; i++) {
			if (voters[i] == msg.sender) {
				voters[i] = voters[nVoters - 1];
				voters.pop();

				break;
			}
		}

		nVoters--;
	}

	/**
	 * Refunds token votes to all voters, if the msg.sender is the governing
	 * contract.
	 */
	function refundAll() external returns (bool) {
		// Not any user can call refund
		require(msg.sender == address(governed), "Refunder is not the governor");

		// Refund all voters
		for (uint i = 0; i < nVoters; i++) {
			address voter = address(voters[i]);

			require(governed.transfer(voter, refunds[voter].votes), "Failed to refund all voters");
		}

		// All voters were successfully refunded
		return true;
	}

	/**
	 * Gets the current funding rate used by the proposal.
	 */
	function finalFundsRate() external view returns (FundingRate memory) {
		return rate;
	}
}

