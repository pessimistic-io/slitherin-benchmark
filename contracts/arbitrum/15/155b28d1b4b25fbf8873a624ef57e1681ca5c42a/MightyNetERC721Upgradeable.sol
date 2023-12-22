// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./ERC721PausableUpgradeable.sol";
import "./ERC721BurnableUpgradeable.sol";
import "./ERC721RoyaltyUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./AccessControlUpgradeable.sol";
import "./Strings.sol";

import "./IMightyNetERC721Assets.sol";
import "./IMightyNetRestrictable.sol";
import "./OperatorFiltererUpgradeable.sol";
import { IOperatorFilterRegistry } from "./IOperatorFilterRegistry.sol";
import { IRestrictedRegistry } from "./IRestrictedRegistry.sol";

error Unauthorized();

abstract contract MightyNetERC721Upgradeable is
	ERC721PausableUpgradeable,
	ERC721BurnableUpgradeable,
	ERC721RoyaltyUpgradeable,
	OwnableUpgradeable,
	AccessControlUpgradeable,
	ReentrancyGuardUpgradeable,
	OperatorFiltererUpgradeable,
	IMightyNetERC721Assets,
	IMightyNetRestrictable
{
	bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

	// ------------------------------
	// 			V1 Variables
	// ------------------------------

	// Metadata
	string public baseURI;
	string public contractURI;

	error TokenIsRestricted(uint256 tokenId);
	IRestrictedRegistry public override restrictedRegistry;

	/*
	 * DO NOT ADD OR REMOVE VARIABLES ABOVE THIS LINE. INSTEAD, CREATE A NEW VERSION SECTION BELOW.
	 * MOVE THIS COMMENT BLOCK TO THE END OF THE LATEST VERSION SECTION PRE-DEPLOYMENT.
	 */

	/// @custom:oz-upgrades-unsafe-allow constructor
	constructor() {
		_disableInitializers();
	}

	function __MightyNetERC721Upgradeable_init(
		string memory baseURI_,
		string memory contractURI_,
		IOperatorFilterRegistry operatorFilterRegistry_,
		IRestrictedRegistry restrictedRegistry_,
		string memory name_,
		string memory symbol_
	) internal onlyInitializing {
		// Call parent initializers
		__ERC721_init(name_, symbol_);
		__ERC721Pausable_init();
		__ERC721Burnable_init();
		__ERC721Royalty_init();
		__Ownable_init();
		__AccessControl_init();
		__ReentrancyGuard_init();
		__OperatorFilterer_init(operatorFilterRegistry_);

		// Set defaults
		_grantRole(DEFAULT_ADMIN_ROLE, msg.sender);

		_setDefaultRoyalty(msg.sender, 750);

		// Set constructor arguments
		setBaseURI(baseURI_);
		setContractURI(contractURI_);

		_setRestrictedRegistry(restrictedRegistry_);
	}

	// ------------------------------
	// 			  Minting
	// ------------------------------

	function mint(address to, uint256 tokenId)
		external
		override
		nonReentrant
		whenNotPaused
		onlyRole(MINTER_ROLE)
	{
		_mint(to, tokenId);
	}

	// ------------------------------
	// 			 Burning
	// ------------------------------

	function _burn(uint256 tokenId)
		internal
		virtual
		override(ERC721Upgradeable, ERC721RoyaltyUpgradeable)
	{
		super._burn(tokenId);
	}

	// ------------------------------
	// 			 Transfers
	// ------------------------------

	function _beforeTokenTransfer(
		address from,
		address to,
		uint256 tokenId,
		uint256 batchSize
	)
		internal
		virtual
		override(ERC721Upgradeable, ERC721PausableUpgradeable)
		whenNotPaused
		onlyAllowedOperator
		onlyAllowUnrestricted(tokenId)
	{
		super._beforeTokenTransfer(from, to, tokenId, batchSize);
	}

	// ------------------------------
	// 			  Queries
	// ------------------------------

	function exists(uint256 tokenId) external view override returns (bool) {
		return _exists(tokenId);
	}

	function tokenURI(uint256 tokenId)
		public
		view
		virtual
		override
		returns (string memory)
	{
		_requireMinted(tokenId);

		return
			bytes(baseURI).length > 0
				? string(
					abi.encodePacked(
						baseURI,
						Strings.toHexString(uint160(address(this)), 20),
						"/",
						Strings.toString(tokenId)
					)
				)
				: "";
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

	function pause() external virtual onlyRole(DEFAULT_ADMIN_ROLE) {
		_pause();
	}

	function unpause() external virtual onlyRole(DEFAULT_ADMIN_ROLE) {
		_unpause();
	}

	// ------------------------------
	// 			 Royalties
	// ------------------------------

	function setDefaultRoyalty(address receiver, uint96 feeNumerator)
		external
		virtual
		onlyRole(DEFAULT_ADMIN_ROLE)
	{
		_setDefaultRoyalty(receiver, feeNumerator);
	}

	function deleteDefaultRoyalty()
		external
		virtual
		onlyRole(DEFAULT_ADMIN_ROLE)
	{
		_deleteDefaultRoyalty();
	}

	function setTokenRoyalty(
		uint256 tokenId,
		address receiver,
		uint96 feeNumerator
	) external virtual onlyRole(DEFAULT_ADMIN_ROLE) {
		_setTokenRoyalty(tokenId, receiver, feeNumerator);
	}

	function resetTokenRoyalty(uint256 tokenId)
		external
		virtual
		onlyRole(DEFAULT_ADMIN_ROLE)
	{
		_resetTokenRoyalty(tokenId);
	}

	// ------------------------------
	// 		 Operator Filterer
	// ------------------------------

	function setOperatorFilterRegistry(
		IOperatorFilterRegistry operatorFilterRegistry_
	) external virtual onlyRole(DEFAULT_ADMIN_ROLE) {
		_setOperatorFilterRegistry(operatorFilterRegistry_);
	}

	// ------------------------------
	// 			  Setters
	// ------------------------------

	function setBaseURI(string memory baseURI_)
		public
		virtual
		onlyRole(DEFAULT_ADMIN_ROLE)
	{
		baseURI = baseURI_;
	}

	function setContractURI(string memory contractURI_)
		public
		virtual
		onlyRole(DEFAULT_ADMIN_ROLE)
	{
		contractURI = contractURI_;
	}

	// ------------------------------
	// 		   Miscellaneous
	// ------------------------------

	function supportsInterface(bytes4 interfaceId)
		public
		view
		virtual
		override(
			ERC721Upgradeable,
			ERC721RoyaltyUpgradeable,
			AccessControlUpgradeable,
			IERC165Upgradeable
		)
		returns (bool)
	{
		return
			interfaceId == type(IMightyNetERC721Assets).interfaceId ||
			super.supportsInterface(interfaceId);
	}

	// ------------------------------
	// 		   Restrict
	// ------------------------------

	function _setRestrictedRegistry(IRestrictedRegistry restrictedRegistry_)
		internal
		virtual
	{
		restrictedRegistry = restrictedRegistry_;
	}

	function setRestrictedRegistry(IRestrictedRegistry restrictedRegistry_)
		external
		virtual
		onlyRole(DEFAULT_ADMIN_ROLE)
	{
		_setRestrictedRegistry(restrictedRegistry_);
	}

	modifier onlyAllowUnrestricted(uint256 tokenId) {
		if (restrictedRegistry.isRestricted(address(this), tokenId)) {
			revert TokenIsRestricted(tokenId);
		}
		_;
	}

	uint256[47] private gap_MightyNetERC721Upgradeable;
}

