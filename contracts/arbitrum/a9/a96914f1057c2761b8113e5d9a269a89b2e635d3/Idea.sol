// SPDX-License-Identifier: MIT

import "./Funding.sol";
import "./Prop.sol";
import "./ERC20.sol";
import "./IERC20.sol";
import "./Strings.sol";

pragma solidity ^0.8.11;

/* Represents the governance contract / semi-fungible NFT of an idea in the
 * value tree. */
contract Idea is ERC20 {
	/* Funding rates for derivative ideas */
	mapping (address => FundingRate) public fundedIdeas;

	/* Ideas connected to the current idea */
	address[] public children;

	/* Proposals submitted to the DAO */
	mapping (address => bool) public propSubmitted;
	address[] public proposals;

	/* The location of the idea on IPFS */
	string public ipfsAddr;

	/* The idea, and its datum have been committed to the blockchain. */
	event IdeaRecorded(string ipfsAddr);

	/* A child idea has had a new funds rate finalized. */
	event IdeaFunded(Prop prop, address to, FundingRate rate);

	/* A proposal was submitted by a user */
	event ProposalSubmitted(Prop prop);

	/* A proposal failed to meet a 51% majority */
	event ProposalRejected(Prop prop);

	/* An instance of a child's funding has been released. */
	event FundingDispersed(address to, FundingRate rate);

	// Ensures that the given address is a funded child idea
	modifier isChild(address child) {
		FundingRate memory rate = fundedIdeas[child];

		// The specified contract must be a child that is funded by this governing contract
		require(rate.value > 0, "Proposal doesn't allocate any funds");

		_;
	}

	/**
	 * Creates a new idea from the given datum stored on IPFS, and idea token attributes.
	 */
	constructor(string memory ideaName, string memory ideaTicker, uint256 ideaShares, string memory datumIpfsHash) ERC20(ideaName, ideaTicker) {
		_mint(msg.sender, ideaShares);
		ipfsAddr = datumIpfsHash;

		emit IdeaRecorded(datumIpfsHash);
	}

	/**
	 * Register a proposal in the registry of current proposals for the DAO.
	 */
	function submitProp(string memory _propName, Idea _jurisdiction, address _toFund, address _token, FundingType _fundingType, uint256 _fundingAmount, string memory _proposalIpfsHash, uint256 _voteExpiry) external {
		require(address(_jurisdiction) == address(this), "Governor of proposal must be this idea");

		Prop proposal = new Prop(_propName, _jurisdiction, _toFund, _token, _fundingType, _fundingAmount, _proposalIpfsHash, _voteExpiry);

		proposals.push(address(proposal));
		propSubmitted[address(proposal)] = true;
		emit ProposalSubmitted(proposal);
	}

	/**
	 * Finalizes the given proposition if it has past its expiry date.
	 */
	function finalizeProp(Prop proposal) external {
		require(block.timestamp >= proposal.expiresAt(), "Vote has not yet terminated.");

		// Refund all voters - this must be completed before the vote can be terminated
		require(proposal.refundAll(), "Failed to refund all voters");

		// The new funds rate must not be recorded unless the proposal passed
		if (proposal.votesFor() <= totalSupply() / 2) {
			emit ProposalRejected(proposal);

			return;
		}

		// Record the new funds rate
		address toFund = proposal.toFund();
		FundingRate memory rate = proposal.finalFundsRate();

		for (uint256 i = 0; i < children.length; i++) {
			if (children[i] == toFund) {
				children[i] = children[children.length - 1];
				children.pop();

				break;
			}
		}

		fundedIdeas[toFund].value = 0;
		children.push(toFund);

		fundedIdeas[toFund] = rate;
		emit IdeaFunded(proposal, toFund, rate);
	}

	/**
	 * Disperses funding to the calling Idea, if it is a child in the
	 * jurisdiction of the current token, and has funds to be allocated.
	 */
	function disperseFunding(address idea) external isChild(idea) {
		FundingRate storage rate = fundedIdeas[idea];

		require(!rate.spent, "Funding already spent");

		// The number of tokens to disperse
		uint256 tokens = rate.value;

		// The governing contract has to have funds left in the designated token to transfer to the child
		// The idea can be rewarded in ETH or an ERC-20
		address thisAddr = address(this);

		if (fundedIdeas[idea].token == address(0x00)) {
			require(thisAddr.balance >= rate.value, "Not enough ETH for designated funds");

			(bool sent, ) = payable(idea).call{value: tokens}("");

			require(sent, "Failed to disperse ETH rewards");
		} else {
			// If the reward is in our own token, mint it
			if (rate.kind == FundingType.MINT) {
				require(rate.token == thisAddr, "Cannot mint funds for a foreign token");

				_mint(idea, tokens);
			} else {
				require(IERC20 (rate.token).transfer(idea, tokens), "Failed to disperse ERC rewards");
			}
		}

		rate.spent = true;

		emit FundingDispersed(idea, rate);
	}

	/**
	 * Gets the number of children funded by the idea.
	 */
	function numChildren() external view returns (uint256) {
		return children.length;
	}
}

