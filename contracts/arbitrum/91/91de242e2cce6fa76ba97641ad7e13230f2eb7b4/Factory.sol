// SPDX-License-Identifier: MIT

import "./Idea.sol";

pragma solidity ^0.8.11;

/**
 * A wrapper for the Idea contract used for centralizing events emitted by the
 * child contract.
 */
contract Factory {
	Idea[] public registry;

	/* A user created an instance of the factory */
	event FactoryCreated();

	/* A user created an instance of the Idea contract. */
	event IdeaCreated(address idea);

	constructor() {
		emit FactoryCreated();
	}

	/**
	 * Calls the constructor on the Idea contract with the specified arguments
	 * and registers it in the registry.
	 */
	function createIdea(string memory ideaName, string memory ideaTicker, uint256 ideaShares, string memory datumIpfsHash) external returns (address) {
		Idea created = new Idea(ideaName, ideaTicker, ideaShares, datumIpfsHash);
		registry.push(created);

		// Notify listeners, and transfer to msg.sender, because the registry is msg.sender
		emit IdeaCreated(address(created));
		require(created.transfer(msg.sender, ideaShares), "Failed to allocate supply.");

		return address(created);
	}
}

