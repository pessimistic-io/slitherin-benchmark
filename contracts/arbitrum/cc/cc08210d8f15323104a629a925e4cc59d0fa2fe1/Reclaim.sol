// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./SemaphoreInterface.sol";
import "./Claims.sol";
import "./Random.sol";
import "./StringUtils.sol";
import "./BytesUtils.sol";

// import "hardhat/console.sol";

error Reclaim__GroupAlreadyExists();
error Reclaim__UserAlreadyMerkelized();

/**
 * Reclaim Beacon contract
 */
contract Reclaim is Initializable, UUPSUpgradeable, OwnableUpgradeable {
	struct Witness {
		/** ETH address of the witness */
		address addr;
		/** Host to connect to the witness */
		string host;
	}

	struct Epoch {
		/** Epoch number */
		uint32 id;
		/** when the epoch changed */
		uint32 timestampStart;
		/** when the epoch will change */
		uint32 timestampEnd;
		/** Witnesses for this epoch */
		Witness[] witnesses;
		/**
		 * Minimum number of witnesses
		 * required to create a claim
		 * */
		uint8 minimumWitnessesForClaimCreation;
	}

	struct Proof {
		Claims.ClaimInfo claimInfo;
		Claims.SignedClaim signedClaim;
	}

	/** list of all epochs */
	Epoch[] public epochs;

	/** address of the semaphore contract */
	address public semaphoreAddress;

	/**
	 * duration of each epoch.
	 * is not a hard duration, but useful for
	 * caching purposes
	 * */
	uint32 public epochDurationS; // 1 day

	/**
	 * current epoch.
	 * starts at 1, so that the first epoch is 1
	 * */
	uint32 public currentEpoch;

	/**
	 * created groups mapping
	 * map groupId with true if already created
	 * */
	mapping(uint256 => bool) createdGroups;

	mapping(uint256 => mapping(string => bool)) isUserMerkelized;

	event EpochAdded(Epoch epoch);

	event GroupCreated(uint256 indexed groupId, string indexed provider);

	event DappCreated(bytes32 indexed dappId);

	bool internal locked;

	mapping(bytes32 => bool) merkelizedUserParams;

	mapping(bytes32 => uint256) dappIdToExternalNullifier;

	// Modifiers
	modifier noReentrant() {
		require(!locked, "No re-entrancy");
		locked = true;
		_;
		locked = false;
	}

	/**
	 * @notice Calls initialize on the base contracts
	 *
	 * @dev This acts as a constructor for the upgradeable proxy contract
	 */
	function initialize(address _semaphoreAddress) external initializer {
		__Ownable_init();
		epochDurationS = 1 days;
		currentEpoch = 0;
		semaphoreAddress = _semaphoreAddress;
	}

	/**
	 * @notice Override of UUPSUpgradeable virtual function
	 *
	 * @dev Function that should revert when `msg.sender` is not authorized to upgrade the contract. Called by
	 * {upgradeTo} and {upgradeToAndCall}.
	 */
	function _authorizeUpgrade(address) internal view override onlyOwner {}

	// epoch functions ---

	/**
	 * Fetch an epoch
	 * @param epoch the epoch number to fetch;
	 * pass 0 to fetch the current epoch
	 */
	function fetchEpoch(uint32 epoch) public view returns (Epoch memory) {
		if (epoch == 0) {
			return epochs[epochs.length - 1];
		}
		return epochs[epoch - 1];
	}

	/**
	 * Get the witnesses that'll sign the claim
	 */
	function fetchWitnessesForClaim(
		uint32 epoch,
		bytes32 identifier,
		uint32 timestampS
	) public view returns (Witness[] memory) {
		Epoch memory epochData = fetchEpoch(epoch);
		bytes memory completeInput = abi.encodePacked(
			// hex encode bytes
			StringUtils.bytes2str(
				// convert bytes32 to bytes
				abi.encodePacked(identifier)
			),
			"\n",
			StringUtils.uint2str(epoch),
			"\n",
			StringUtils.uint2str(epochData.minimumWitnessesForClaimCreation),
			"\n",
			StringUtils.uint2str(timestampS)
		);
		bytes memory completeHash = abi.encodePacked(keccak256(completeInput));

		Witness[] memory witnessesLeftList = epochData.witnesses;
		Witness[] memory selectedWitnesses = new Witness[](
			epochData.minimumWitnessesForClaimCreation
		);
		uint witnessesLeft = witnessesLeftList.length;

		uint byteOffset = 0;
		for (uint32 i = 0; i < epochData.minimumWitnessesForClaimCreation; i++) {
			uint randomSeed = BytesUtils.bytesToUInt(completeHash, byteOffset);
			uint witnessIndex = randomSeed % witnessesLeft;
			selectedWitnesses[i] = witnessesLeftList[witnessIndex];
			// remove the witness from the list of witnesses
			// we've utilised witness at index "idx"
			// we of course don't want to pick the same witness twice
			// so we remove it from the list of witnesses
			// and reduce the number of witnesses left to pick from
			// since solidity doesn't support "pop()" in memory arrays
			// we swap the last element with the element we want to remove
			witnessesLeftList[witnessIndex] = epochData.witnesses[witnessesLeft - 1];
			byteOffset = (byteOffset + 4) % completeHash.length;
			witnessesLeft -= 1;
		}

		return selectedWitnesses;
	}

	function createDapp(uint256 id) external {
		bytes32 dappId = keccak256(abi.encodePacked(msg.sender, id));
		require(dappIdToExternalNullifier[dappId] != id, "Dapp Already Exists");
		dappIdToExternalNullifier[dappId] = id;
		emit DappCreated(dappId);
	}

	/**
	 * Get the provider name from the proof
	 */
	function getProviderFromProof(
		Proof memory proof
	) external pure returns (string memory) {
		return proof.claimInfo.provider;
	}

	/**
	 * Get the context message from the proof
	 */
	function getContextMessageFromProof(
		Proof memory proof
	) external pure returns (string memory) {
		string memory context = proof.claimInfo.context;
		return StringUtils.substring(context, 42, bytes(context).length);
	}

	/**
	 * Get the context address from the proof
	 */
	function getContextAddressFromProof(
		Proof memory proof
	) public pure returns (string memory) {
		string memory context = proof.claimInfo.context;
		return StringUtils.substring(context, 0, 42);
	}

	function getMerkelizedUserParams(
		string memory provider,
		string memory params
	) external view returns (bool) {
		bytes32 userParamsHash = calculateUserParamsHash(provider, params);
		return merkelizedUserParams[userParamsHash];
	}

	/**
	 * Call the function to assert
	 * the validity of several claims proofs
	 */
	function verifyProof(Proof memory proof) public returns (bool) {
		// create signed claim using claimData and signature.
		require(proof.signedClaim.signatures.length > 0, "No signatures");
		Claims.SignedClaim memory signed = Claims.SignedClaim(
			proof.signedClaim.claim,
			proof.signedClaim.signatures
		);

		// check if the hash from the claimInfo is equal to the infoHash in the claimData
		bytes32 hashed = Claims.hashClaimInfo(proof.claimInfo);
		require(proof.signedClaim.claim.identifier == hashed);

		// fetch witness list from fetchEpoch(_epoch).witnesses
		Witness[] memory expectedWitnesses = fetchWitnessesForClaim(
			proof.signedClaim.claim.epoch,
			proof.signedClaim.claim.identifier,
			proof.signedClaim.claim.timestampS
		);
		address[] memory signedWitnesses = Claims.recoverSignersOfSignedClaim(signed);
		// check if the number of signatures is equal to the number of witnesses
		require(
			signedWitnesses.length == expectedWitnesses.length,
			"Number of signatures not equal to number of witnesses"
		);

		// Update awaited: more checks on whose signatures can be considered.
		for (uint256 i = 0; i < signed.signatures.length; i++) {
			bool found = false;
			for (uint j = 0; j < expectedWitnesses.length; j++) {
				if (signedWitnesses[i] == expectedWitnesses[j].addr) {
					found = true;
					break;
				}
			}
			require(found, "Signature not appropriate");
		}

		//@TODO: verify zkproof
		return true;
	}

	function createGroup(
		string memory provider,
		uint256 merkleTreeDepth // address admin
	) public {
		uint256 groupId = calculateGroupIdFromProvider(provider);
		if (createdGroups[groupId] == true) {
			revert Reclaim__GroupAlreadyExists();
		}
		SemaphoreInterface(semaphoreAddress).createGroup(
			groupId,
			merkleTreeDepth,
			address(this)
		);
		createdGroups[groupId] = true;
		emit GroupCreated(groupId, provider);
	}

	function merkelizeUser(
		Proof memory proof,
		uint256 _identityCommitment
	) external noReentrant {
		uint256 groupId = calculateGroupIdFromProvider(proof.claimInfo.provider);
		bytes32 userParamsHash = calculateUserParamsHash(
			proof.claimInfo.provider,
			proof.claimInfo.parameters
		);
		if (merkelizedUserParams[userParamsHash] == true) {
			revert Reclaim__UserAlreadyMerkelized();
		}
		verifyProof(proof);
		if (createdGroups[groupId] != true) {
			createGroup(proof.claimInfo.provider, 20);
		}
		SemaphoreInterface(semaphoreAddress).addMember(groupId, _identityCommitment);
		merkelizedUserParams[userParamsHash] = true;
	}

	function verifyMerkelIdentity(
		string memory provider,
		uint256 _merkleTreeRoot,
		uint256 _signal,
		uint256 _nullifierHash,
		uint256 _externalNullifier,
		bytes32 dappId,
		uint256[8] calldata _proof
	) external returns (bool) {
		require(
			dappIdToExternalNullifier[dappId] == _externalNullifier,
			"Dapp Not Created"
		);
		uint256 groupId = calculateGroupIdFromProvider(provider);
		try
			SemaphoreInterface(semaphoreAddress).verifyProof(
				groupId,
				_merkleTreeRoot,
				_signal,
				_nullifierHash,
				_externalNullifier,
				_proof
			)
		{
			return true;
		} catch {
			return false;
		}
	}

	// admin functions ---

	/**
	 * @dev Add a new epoch
	 */
	function addNewEpoch(
		Witness[] calldata witnesses,
		uint8 requisiteWitnessesForClaimCreate
	) external onlyOwner {
		if (epochDurationS == 0) {
			epochDurationS = 1 days;
		}
		if (epochs.length > 0) {
			epochs[epochs.length - 1].timestampEnd = uint32(block.timestamp);
		}

		currentEpoch += 1;
		Epoch storage epoch = epochs.push();
		epoch.id = currentEpoch;
		epoch.timestampStart = uint32(block.timestamp);
		epoch.timestampEnd = uint32(block.timestamp + epochDurationS);
		epoch.minimumWitnessesForClaimCreation = requisiteWitnessesForClaimCreate;

		for (uint256 i = 0; i < witnesses.length; i++) {
			epoch.witnesses.push(witnesses[i]);
		}

		emit EpochAdded(epochs[epochs.length - 1]);
	}

	// internal code -----

	function uintDifference(uint256 a, uint256 b) internal pure returns (uint256) {
		if (a > b) {
			return a - b;
		}

		return b - a;
	}

	/**
	 * @dev Get/Calculate the groupId for a specific provider
	 */
	function calculateGroupIdFromProvider(
		string memory provider
	) internal pure returns (uint256) {
		bytes memory providerBytes = bytes(provider);
		bytes memory hashedProvider = abi.encodePacked(keccak256(providerBytes));
		uint256 groupId = BytesUtils.bytesToUInt(
			hashedProvider,
			hashedProvider.length - 4
		);
		return groupId;
	}

	function calculateUserParamsHash(
		string memory provider,
		string memory params
	) internal pure returns (bytes32) {
		bytes32 userParamsHash = keccak256(abi.encodePacked(provider, params));
		return userParamsHash;
	}
}

