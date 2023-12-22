// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { IGenericRewardDistributor } from "./IGenericRewardDistributor.sol";
import { OwnableWithTransfer } from "./OwnableWithTransfer.sol";

// import "hardhat/console.sol";

struct RewardClaim {
	address distributor;
	uint256 amount;
	bytes32[] proof;
}

/// @title MerkleClaimer
/// @notice This contract claims rewards from multiple merkle distributors
contract MerkleClaimer is OwnableWithTransfer {
	mapping(address => bool) public whitelist;

	/// @param merkleDistributors whitelisted reward distributors
	constructor(address[] memory merkleDistributors) OwnableWithTransfer(msg.sender) {
		for (uint256 i = 0; i < merkleDistributors.length; ++i) {
			whitelist[merkleDistributors[i]] = true;
		}
	}

	/// @notice whitelists a reward distributor
	/// @param _address the address to whitelist
	function updateWhitelist(address _address, bool status) external onlyOwner {
		whitelist[_address] = status;
		emit UpdateWhitelist(_address, status);
	}

	/// @notice Claims rewards from multiple rewardDistributors.
	/// @param account The account to claim for
	/// @param claims The claims to make
	function claim(address account, RewardClaim[] calldata claims) external {
		for (uint256 i = 0; i < claims.length; ++i) {
			// only whitelisted distributors can be claimed from
			if (!whitelist[claims[i].distributor]) revert NotWhitelisted();
			IGenericRewardDistributor(claims[i].distributor).claim(
				account,
				claims[i].amount,
				claims[i].proof
			);
		}
	}

	error NotWhitelisted();
	event UpdateWhitelist(address indexed _address, bool status);
}

