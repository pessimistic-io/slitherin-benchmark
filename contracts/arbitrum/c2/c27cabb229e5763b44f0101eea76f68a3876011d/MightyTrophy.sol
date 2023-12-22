// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

/*
 * Copyright (c) 2022 Mighty Bear Games
 */

import "./ERC721SoulboundUpgradeable.sol";
import "./Counters.sol";

error Unauthorized();
error WrongId();

contract MightyTrophy is ERC721SoulboundUpgradeable {
	using Counters for Counters.Counter;

	// ------------------------------
	// 			V1 Variables
	// ------------------------------
	Counters.Counter private _tokenIdCounter;

	// Metadata
	string public baseURI;
	string public contractURI;

	// Minting
	address public minter;

	/*
	 * DO NOT ADD OR REMOVE VARIABLES ABOVE THIS LINE. INSTEAD, CREATE A NEW VERSION SECTION BELOW.
	 * MOVE THIS COMMENT BLOCK TO THE END OF THE LATEST VERSION SECTION PRE-DEPLOYMENT.
	 */

	/// @custom:oz-upgrades-unsafe-allow constructor
	constructor() {
		_disableInitializers();
	}

	function initialize(
		string memory baseURI_,
		string memory contractURI_
	) public initializer {
		// call parent initializers
		__ERC721_init("Mighty Trophy", "MTT");
		__ERC721Pausable_init();
		__ERC721Burnable_init();
		__Ownable_init();
		__AccessControl_init();
		__ReentrancyGuard_init();

		// Set defaults
		_grantRole(DEFAULT_ADMIN_ROLE, msg.sender);

		// Set constructor arguments
		setBaseURI(baseURI_);
		setContractURI(contractURI_);
		setMinter(msg.sender);

		// mint the first token to set up collection
		_adminMint(msg.sender);
	}

	// ------------------------------
	// 			  Setters
	// ------------------------------

	function setBaseURI(
		string memory baseURI_
	) public onlyRole(DEFAULT_ADMIN_ROLE) {
		baseURI = baseURI_;
	}

	function setContractURI(
		string memory contractURI_
	) public onlyRole(DEFAULT_ADMIN_ROLE) {
		contractURI = contractURI_;
	}

	function setMinter(address minter_) public onlyRole(DEFAULT_ADMIN_ROLE) {
		minter = minter_;
	}

	// ------------------------------
	// 			 Minting
	// ------------------------------

	function _adminMint(
		address to
	) internal nonReentrant whenNotPaused onlyRole(DEFAULT_ADMIN_ROLE) {
		uint256 tokenId = _tokenIdCounter.current();
		_tokenIdCounter.increment();
		_safeMint(to, tokenId);
	}

	function batchMint(
		address[] calldata to,
		uint256[] calldata ids
	) external nonReentrant whenNotPaused onlyMinter {
		for (uint256 i = 0; i < to.length; ++i) {
			if (ids[i] != _tokenIdCounter.current()) {
				revert WrongId();
			}
			uint256 tokenId = _tokenIdCounter.current();
			_tokenIdCounter.increment();
			_safeMint(to[i], tokenId);
		}
	}

	// ------------------------------
	// 			 Burning
	// ------------------------------

	function _burn(
		uint256 tokenId
	) internal virtual override(ERC721Upgradeable) {
		super._burn(tokenId);
	}

	// ------------------------------
	// 			  Queries
	// ------------------------------

	function exists(uint256 tokenId) external view returns (bool) {
		return _exists(tokenId);
	}

	// ------------------------------
	// 			  Metadata
	// ------------------------------

	function _baseURI() internal view override returns (string memory) {
		return baseURI;
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
	// 			  Modifiers
	// ------------------------------

	modifier onlyMinter() {
		if (msg.sender != minter) {
			revert Unauthorized();
		}
		_;
	}
}

