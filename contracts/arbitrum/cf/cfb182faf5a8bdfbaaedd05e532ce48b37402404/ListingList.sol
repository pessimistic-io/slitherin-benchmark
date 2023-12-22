pragma solidity 0.8.13;

// SPDX-License-Identifier: MIT

import "./Ownable.sol";
import "./IERC20.sol";
import "./ERC721.sol";

/// @title ListingList
/// @notice Contract for recording nft contracts eligible for Zoo Dao Battles.
contract ListingList is Ownable, ERC721
{
	struct CollectionRecord
	{
		uint256 decayRate;
		uint256 rateOfIncrease;
		uint256 weightAtTheStart;
	}

	struct VePositionInfo
	{
		uint256 expirationDate;
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

	mapping (address => uint256) public lastUpdatedEpochsForCollection;

	// Nft contract => allowed or not.
	mapping (address => bool) public eligibleCollections;

	// Nft contract => address recipient.
	mapping (address => address) public royalteRecipient;

	// collection => epoch number => Record
	mapping (address => mapping (uint256 => CollectionRecord)) public collectionRecords;

	mapping (uint256 => VePositionInfo) public vePositions;

	mapping (address => uint256[]) public tokenOfOwnerByIndex;

	uint256 public epochDuration;

	uint256 public startDate;

	uint256 public minTimelock;

	uint256 public maxTimelock;

	uint256 public vePositionIndex = 1;

	uint256 public endEpochOfIncentiveRewards;

	constructor(address _zoo, uint256 _duration, uint256 _minTimelock, uint256 _maxTimelock, uint256 _incentiveRewardsDuration) ERC721("veZoo", "VEZOO")
	{
		require(_minTimelock <= _duration, "Duration should be more than minTimeLock");

		zoo = IERC20(_zoo);
		startDate = block.timestamp;
		epochDuration = _duration;
		minTimelock = _minTimelock;
		maxTimelock = _maxTimelock;
		endEpochOfIncentiveRewards = _incentiveRewardsDuration / _duration + 1;
	}

	function getEpochNumber(uint256 timestamp) public view returns (uint256)
	{
		return (timestamp - startDate) / epochDuration + 1;// epoch numbers must start from 1
	}

	function getVectorForEpoch(address collection, uint256 epochIndex) public view returns (uint256)
	{
		require(lastUpdatedEpochsForCollection[collection] >= epochIndex, "Epoch record was not updated");

		return computeVectorForEpoch(collection, epochIndex);
	}

	// address(0) for total (collection sum)
	/// @notice Function to get ve-model pool weight for nft collection.
	function poolWeight(address collection, uint256 epochIndex) public view returns(uint256 weight)
	{
		require(lastUpdatedEpochsForCollection[collection] >= epochIndex, "Epoch and colletion records were not updated");

		return collectionRecords[collection][epochIndex].weightAtTheStart;
	}

	function updateCurrentEpochAndReturnPoolWeight(address collection) public returns (uint256 weight)
	{
		uint256 epochNumber = getEpochNumber(block.timestamp);
		uint256 i = lastUpdatedEpochsForCollection[collection];
		weight = poolWeight(collection, i);

		while (i < epochNumber)
		{
			CollectionRecord storage collectionRecord = collectionRecords[collection][i + 1];
			CollectionRecord storage collectionRecordOfPreviousEpoch = collectionRecords[collection][i];

			uint256 decreasingOfWeight = computeVectorForEpoch(collection, i) * epochDuration;
			if (collectionRecordOfPreviousEpoch.weightAtTheStart + collectionRecord.weightAtTheStart >= decreasingOfWeight)
				collectionRecord.weightAtTheStart = collectionRecord.weightAtTheStart + collectionRecordOfPreviousEpoch.weightAtTheStart - decreasingOfWeight;
			else
				collectionRecord.weightAtTheStart = 0;

			collectionRecord.decayRate += collectionRecordOfPreviousEpoch.decayRate;
			collectionRecord.rateOfIncrease += collectionRecordOfPreviousEpoch.rateOfIncrease;

			i++;
			weight = collectionRecord.weightAtTheStart;
		}

		lastUpdatedEpochsForCollection[collection] = epochNumber;
	}

/* ========== Eligible projects and royalte managemenet ===========*/

	/// @notice Function to allow new NFT contract into eligible projects.
	/// @param collection - address of new Nft contract.
	function allowNewContractForStaking(address collection, address _royalteRecipient) external onlyOwner
	{
		eligibleCollections[collection] = true;                                          // Boolean for contract to be allowed for staking.

		royalteRecipient[collection] = _royalteRecipient;                                // Recipient for % of reward from that nft collection.

		lastUpdatedEpochsForCollection[collection] = getEpochNumber(block.timestamp);

		emit NewContractAllowed(collection, _royalteRecipient);                                             // Emits event that new contract are allowed.
	}

	/// @notice Function to allow multiplie contracts into eligible projects.
	function batchAllowNewContract(address[] calldata tokens, address[] calldata royalteRecipients) external onlyOwner
	{
		for (uint256 i = 0; i < tokens.length; i++)
		{
			eligibleCollections[tokens[i]] = true;

			royalteRecipient[tokens[i]] = royalteRecipients[i];                     // Recipient for % of reward from that nft collection.

			lastUpdatedEpochsForCollection[tokens[i]] = getEpochNumber(block.timestamp);

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
	
	function voteForNftCollection(address collection, uint256 amount, uint256 lockTime) public
	{
		require(eligibleCollections[collection], "NFT collection is not allowed");
		require(lockTime <= maxTimelock && lockTime >= minTimelock, "incorrect lockTime");

		zoo.transferFrom(msg.sender, address(this), amount);

		addRecordForNewPosition(collection, amount, lockTime, msg.sender, vePositionIndex);

		tokenOfOwnerByIndex[msg.sender].push(vePositionIndex);
		_mint(msg.sender, vePositionIndex++);
	}

	function unlockZoo(uint256 positionId) external
	{
		require(ownerOf(positionId) == msg.sender);
		VePositionInfo storage vePosition = vePositions[positionId];

		uint256 currentEpoch = getEpochNumber(block.timestamp);

		require(block.timestamp >= vePosition.expirationDate, "time lock doesn't expire");

		zoo.transfer(msg.sender, vePosition.zooLocked);
		_burn(positionId);

		emit ZooUnlocked(msg.sender, vePosition.collection, vePosition.zooLocked, positionId);
	}

	function prolongate(uint256 positionId, uint256 lockTime) external
	{
		require(lockTime <= maxTimelock && lockTime >= minTimelock, "incorrect lockTime");
		require(ownerOf(positionId) == msg.sender);

		VePositionInfo storage vePosition = vePositions[positionId];

		uint256 currentEpoch = getEpochNumber(block.timestamp);
		uint256 expirationEpoch = getEpochNumber(vePosition.expirationDate);
		address collection = vePosition.collection;
		uint256 decayRate = vePosition.decayRate;

		updateCurrentEpochAndReturnPoolWeight(collection);
		updateCurrentEpochAndReturnPoolWeight(address(0));

		if (vePosition.expirationDate > block.timestamp) // If position has not expired yet. We need to liquidate it and recreate.
		{
			collectionRecords[collection][expirationEpoch].rateOfIncrease -= decayRate;
			collectionRecords[collection][currentEpoch + 1].rateOfIncrease += decayRate;
			collectionRecords[address(0)][expirationEpoch].rateOfIncrease -= decayRate;
			collectionRecords[address(0)][currentEpoch + 1].rateOfIncrease += decayRate;
		}

		addRecordForNewPosition(collection, vePosition.zooLocked, lockTime, msg.sender, positionId);
	}

	function addRecordForNewPosition(address collection, uint256 amount, uint256 lockTime, address owner, uint256 positionId) internal
	{
		uint256 weight = amount * lockTime / maxTimelock;
		uint256 currentEpoch = getEpochNumber(block.timestamp);

		uint256 unlockEpoch = getEpochNumber(block.timestamp + lockTime);
		uint256 decay = weight / lockTime;
		vePositions[positionId] = VePositionInfo(block.timestamp + lockTime, amount, collection, decay);

		collectionRecords[address(0)][currentEpoch + 1].decayRate += decay;
		collectionRecords[address(0)][currentEpoch + 1].weightAtTheStart += weight;
		collectionRecords[collection][currentEpoch + 1].decayRate += decay;
		collectionRecords[collection][currentEpoch + 1].weightAtTheStart += weight;

		collectionRecords[address(0)][unlockEpoch].rateOfIncrease += decay;
		collectionRecords[collection][unlockEpoch].rateOfIncrease += decay;
		
		emit VotedForCollection(collection, msg.sender, amount, positionId);
	}

	function computeVectorForEpoch(address collection, uint256 epochIndex) internal view returns (uint256)
	{
		CollectionRecord storage collectionRecord = collectionRecords[collection][epochIndex];

		return collectionRecord.decayRate - collectionRecord.rateOfIncrease;
	}
}
