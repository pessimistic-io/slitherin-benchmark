/*
 * Copyright (c) 2023 Mighty Bear Games
 */
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./AccessControlUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./IMightyNetRestrictable.sol";
import { IRestrictedRegistry } from "./IRestrictedRegistry.sol";
import { ERC721Restrictable } from "./ERC721Restrictable.sol";

error InvalidToken(address tokenContract, uint256 count);
error InvalidTokenCount(uint256 count);
error InvalidRestrictor(address restrictor);
error TokenAlreadyRestricted(address tokenContract, uint256 tokenId);
error TokenNotRestricted(address tokenContract, uint256 tokenId);
error ContractNotUsingThisRestrictedRegistry(address tokenContract);

contract MightyNetERC721RestrictedRegistryV2 is
	AccessControlUpgradeable,
	PausableUpgradeable,
	ReentrancyGuardUpgradeable,
	IRestrictedRegistry
{
	// ------------------------------
	// 			V1 Variables
	// ------------------------------

	event Restricted(address tokenContact, uint256[] tokenIds);
	event Unrestricted(address tokenContract, uint256[] tokenIds);

	mapping(address => mapping(uint256 => address)) private _tokenRestrictions;

	bytes32 public constant RESTRICTOR_ROLE = keccak256("RESTRICTOR_ROLE");

	/*
	 * DO NOT ADD OR REMOVE VARIABLES ABOVE THIS LINE. INSTEAD, CREATE A NEW VERSION SECTION BELOW.
	 * MOVE THIS COMMENT BLOCK TO THE END OF THE LATEST VERSION SECTION PRE-DEPLOYMENT.
	 */

	/// @custom:oz-upgrades-unsafe-allow constructor
	constructor() {
		_disableInitializers();
	}

	function initialize() public initializer {
		__AccessControl_init();
		__Pausable_init();
		__ReentrancyGuard_init();
		_grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
	}

	function isRestricted(address tokenContract, uint256 tokenId)
		public
		view
		override
		returns (bool)
	{
		return _isRestricted(tokenContract, tokenId);
	}

	function _isRestricted(address tokenContract, uint256 tokenId)
		internal
		view
		returns (bool)
	{
		return _tokenRestrictions[tokenContract][tokenId] != address(0);
	}

	function restrict(address tokenContract, uint256[] calldata tokenIds)
		external
		override
		onlyRole(RESTRICTOR_ROLE)
		nonReentrant
		whenNotPaused
	{
		if (
			address(
				IMightyNetRestrictable(tokenContract).restrictedRegistry()
			) != address(this)
		) {
			revert ContractNotUsingThisRestrictedRegistry(tokenContract);
		}
		uint256 tokenCount = tokenIds.length;
		if (tokenCount == 0) {
			revert InvalidTokenCount(tokenCount);
		}
		for (uint256 i = 0; i < tokenCount; ++i) {
			uint256 tokenId = tokenIds[i];
			if (!ERC721Restrictable(tokenContract).exists(tokenId)) {
				revert InvalidToken(tokenContract, tokenId);
			}
			if (_isRestricted(tokenContract, tokenId)) {
				revert TokenAlreadyRestricted(tokenContract, tokenId);
			}
			_tokenRestrictions[tokenContract][tokenId] = msg.sender;
		}
		emit Restricted(tokenContract, tokenIds);
	}

	function unrestrict(address tokenContract, uint256[] calldata tokenIds)
		external
		override
		onlyRole(RESTRICTOR_ROLE)
		nonReentrant
		whenNotPaused
	{
		uint256 tokenCount = tokenIds.length;
		if (tokenCount == 0) {
			revert InvalidTokenCount(tokenCount);
		}
		for (uint256 i = 0; i < tokenCount; ++i) {
			uint256 tokenId = tokenIds[i];
			if (!ERC721Restrictable(tokenContract).exists(tokenId)) {
				revert InvalidToken(tokenContract, tokenId);
			}
			if (!_isRestricted(tokenContract, tokenId)) {
				revert TokenNotRestricted(tokenContract, tokenId);
			}
			if (_tokenRestrictions[tokenContract][tokenId] != msg.sender) {
				revert InvalidRestrictor(msg.sender);
			}
			_tokenRestrictions[tokenContract][tokenId] = address(0);
		}
		emit Unrestricted(tokenContract, tokenIds);
	}

	function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
		_pause();
	}

	function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
		_unpause();
	}
}

