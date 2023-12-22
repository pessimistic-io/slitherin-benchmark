// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./MightyNetERC1155Upgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./AccessControlUpgradeable.sol";
import "./PausableUpgradeable.sol";

import "./Whitelists.sol";

error NotWhitelisted(address address_);
error InvalidIndex(uint256 whitelistIndex);
error UserAlreadyClaimed(address address_);

contract MightyNetERC1155Claimer is
	AccessControlUpgradeable,
	PausableUpgradeable,
	ReentrancyGuardUpgradeable
{
	// ------------------------------
	// 			V1 Variables
	// ------------------------------

	MightyNetERC1155Upgradeable public mnERC1155;

	using Whitelists for Whitelists.MerkleProofWhitelist;

	Whitelists.MerkleProofWhitelist[] private claimWhitelist;

	mapping(address => bool) public addressToHaveClaimed;

	uint256 public tokenId;

	/*
	 * DO NOT ADD OR REMOVE VARIABLES ABOVE THIS LINE. INSTEAD, CREATE A NEW VERSION SECTION BELOW.
	 * MOVE THIS COMMENT BLOCK TO THE END OF THE LATEST VERSION SECTION PRE-DEPLOYMENT.
	 */

	/// @custom:oz-upgrades-unsafe-allow constructor
	constructor() {
		_disableInitializers();
	}

	function initialize(MightyNetERC1155Upgradeable mnERC1155_)
		public
		initializer
	{
		__AccessControl_init();
		__Pausable_init();
		__ReentrancyGuard_init();

		_grantRole(DEFAULT_ADMIN_ROLE, msg.sender);

		setMightyNetERC1155Address(mnERC1155_);
	}

	// ------------------------------
	// 		   Claim
	// ------------------------------

	function claim(bytes32[] calldata merkleProof)
		external
		payable
		nonReentrant
		whenNotPaused
		onlyWhitelisted(msg.sender, merkleProof, claimWhitelist)
	{
		if (addressToHaveClaimed[msg.sender]) {
			revert UserAlreadyClaimed(msg.sender);
		}
		uint256 size = claimWhitelist.length;
		bool whitelisted = false;
		uint256 toMint = 0;
		for (; toMint < size; ++toMint) {
			if (claimWhitelist[toMint].isWhitelisted(msg.sender, merkleProof)) {
				whitelisted = true;
				break;
			}
		}

		if (!whitelisted) {
			revert NotWhitelisted(msg.sender);
		}

		addressToHaveClaimed[msg.sender] = true;
		mnERC1155.mint(msg.sender, tokenId, toMint + 1);
	}

	// ------------------------------
	// 		   Query
	// ------------------------------

	function amountClaimable(address user, bytes32[] calldata merkleProof)
		external
		view
		returns (uint256)
	{
		uint256 size = claimWhitelist.length;

		if (addressToHaveClaimed[user]) {
			return 0;
		}

		for (uint256 i = 0; i < size; ++i) {
			if (claimWhitelist[i].isWhitelisted(user, merkleProof)) {
				return i + 1;
			}
		}

		return 0;
	}

	function claimWhitelistMerkleRoot(uint256 index)
		external
		view
		returns (bytes32)
	{
		return claimWhitelist[index].getRootHash();
	}

	function claimWhitelistSize() external view returns (uint256) {
		return claimWhitelist.length;
	}

	// ------------------------------
	// 			  Pausing
	// ------------------------------

	function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
		_pause();
	}

	function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
		_unpause();
	}

	// ------------------------------
	// 			  Setters
	// ------------------------------

	function setMightyNetERC1155Address(MightyNetERC1155Upgradeable mnERC1155_)
		public
		onlyRole(DEFAULT_ADMIN_ROLE)
	{
		mnERC1155 = mnERC1155_;
	}

	function setTokenId(uint256 id_) public onlyRole(DEFAULT_ADMIN_ROLE) {
		tokenId = id_;
	}

	function setClaimWhitelistMerkleRoot(
		bytes32 rootHash,
		uint256 whitelistIndex
	) external onlyRole(DEFAULT_ADMIN_ROLE) {
		if (whitelistIndex >= claimWhitelist.length) {
			revert InvalidIndex(whitelistIndex);
		}

		claimWhitelist[whitelistIndex].setRootHash(rootHash);
	}

	function pushToClaimWhitelist(bytes32 rootHash)
		external
		onlyRole(DEFAULT_ADMIN_ROLE)
	{
		claimWhitelist.push(Whitelists.MerkleProofWhitelist(rootHash));
	}

	function popFromClaimWhitelist() external onlyRole(DEFAULT_ADMIN_ROLE) {
		claimWhitelist.pop();
	}

	// ------------------------------
	// 			  Modifiers
	// ------------------------------

	modifier onlyWhitelisted(
		address user,
		bytes32[] calldata merkleProof,
		Whitelists.MerkleProofWhitelist[] storage whitelist
	) {
		_;
	}
}

