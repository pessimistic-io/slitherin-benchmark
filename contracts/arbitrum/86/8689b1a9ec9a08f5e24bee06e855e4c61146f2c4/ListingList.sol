pragma solidity 0.8.13;

// SPDX-License-Identifier: MIT

import "./Ownable.sol";
import "./IERC20.sol";
import "./ERC721.sol";

interface INftBattleArena
{
	function addVotesToVeZoo(address collection, uint256 amount) external;

	function removeVotesFromVeZoo(address collection, uint256 amount) external;
}

/// @title ListingList
/// @notice Contract for recording nft contracts eligible for Zoo Dao Battles.
contract ListingList is Ownable, ERC721
{
	struct VePositionInfo
	{
		uint256 zooLocked;
		address collection;
		uint256 decayRate;
	}

	IERC20 public zoo;                                                               // Zoo collection interface.

	/// @notice Event records address of allowed nft contract.
	event NewContractAllowed(address indexed collection, address royalteRecipient);

	event ContractDisallowed(address indexed collection, address royalteRecipient);

	event RoyalteRecipientChanged(address indexed collection, address recipient);

	event VotedForCollection(address indexed collection, address indexed voter, uint256 amount, uint256 positionId);

	event ZooUnlocked(address indexed voter, address indexed collection, uint256 amount, uint256 positionId);

	// Nft contract => allowed or not.
	mapping (address => bool) public eligibleCollections;

	// Nft contract => address recipient.
	mapping (address => address) public royalteRecipient;

	mapping (uint256 => VePositionInfo) public vePositions;

	mapping (address => uint256[]) public tokenOfOwnerByIndex;

	uint256 public vePositionIndex = 1;

	uint256 public endEpochOfIncentiveRewards;

	INftBattleArena public arena;

	constructor(address _zoo, uint256 _endEpochOfIncentiveRewards) ERC721("veZoo", "VEZOO")
	{
		zoo = IERC20(_zoo);
		endEpochOfIncentiveRewards = _endEpochOfIncentiveRewards;
	}

	function init(address nftBattleArena) external
	{
		require(address(arena) == address(0), "Var has already inited");

		arena = INftBattleArena(nftBattleArena);
	}

/* ========== Eligible projects and royalte managemenet ===========*/

	/// @notice Function to allow new NFT contract into eligible projects.
	/// @param collection - address of new Nft contract.
	function allowNewContractForStaking(address collection, address _royalteRecipient) external onlyOwner
	{
		eligibleCollections[collection] = true;                                          // Boolean for contract to be allowed for staking.

		royalteRecipient[collection] = _royalteRecipient;                                // Recipient for % of reward from that nft collection.

		emit NewContractAllowed(collection, _royalteRecipient);                                             // Emits event that new contract are allowed.
	}

	/// @notice Function to allow multiplie contracts into eligible projects.
	function batchAllowNewContract(address[] calldata tokens, address[] calldata royalteRecipients) external onlyOwner
	{
		for (uint256 i = 0; i < tokens.length; i++)
		{
			eligibleCollections[tokens[i]] = true;

			royalteRecipient[tokens[i]] = royalteRecipients[i];                     // Recipient for % of reward from that nft collection.

			emit NewContractAllowed(tokens[i], royalteRecipients[i]);                                     // Emits event that new contract are allowed.
		}
	}

	/// @notice Function to disallow contract from eligible projects and change royalte recipient for already staked nft.
	function disallowContractFromStaking(address collection, address recipient) external onlyOwner
	{
		eligibleCollections[collection] = false;

		royalteRecipient[collection] = recipient;                                        // Recipient for % of reward from that nft collection.

		emit ContractDisallowed(collection, recipient);                                             // Emits event that new contract are allowed.
	}

	/// @notice Function to set or change royalte recipient without removing from eligible projects.
	function setRoyalteRecipient(address collection, address recipient) external onlyOwner
	{
		royalteRecipient[collection] = recipient;

		emit RoyalteRecipientChanged(collection, recipient);
	}

/* ========== Ve-Model voting part ===========*/
	
	function voteForNftCollection(address collection, uint256 amount) public
	{
		require(eligibleCollections[collection], "NFT collection is not allowed");

		zoo.transferFrom(msg.sender, address(this), amount);

		vePositions[vePositionIndex] = VePositionInfo(amount, collection, 0);
		arena.addVotesToVeZoo(collection, amount * 3 / 2);

		tokenOfOwnerByIndex[msg.sender].push(vePositionIndex);
		emit VotedForCollection(collection, msg.sender, amount, vePositionIndex);
		_mint(msg.sender, vePositionIndex++);
	}

	function unlockZoo(uint256 positionId) external
	{
		require(ownerOf(positionId) == msg.sender);
		VePositionInfo storage vePosition = vePositions[positionId];

		arena.removeVotesFromVeZoo(vePosition.collection, vePosition.zooLocked * 3 / 2);
		zoo.transfer(msg.sender, vePosition.zooLocked);
		_burn(positionId);

		emit ZooUnlocked(msg.sender, vePosition.collection, vePosition.zooLocked, positionId);
	}
}
