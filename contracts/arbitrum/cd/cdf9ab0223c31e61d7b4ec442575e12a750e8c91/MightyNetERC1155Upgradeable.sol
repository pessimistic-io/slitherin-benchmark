// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./ERC1155Upgradeable.sol";
import "./ERC1155PausableUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./AccessControlUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./Strings.sol";

import "./IMightyNetERC1155Assets.sol";
import "./OperatorFiltererUpgradeable.sol";

error Unauthorized();

// ERC 1155 Do not have royalty standard during implementation
abstract contract MightyNetERC1155Upgradeable is
	ERC1155PausableUpgradeable,
	OwnableUpgradeable,
	AccessControlUpgradeable,
	ReentrancyGuardUpgradeable,
	OperatorFiltererUpgradeable,
	IMightyNetERC1155Assets
{
	bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
	bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");

	// ------------------------------
	// 			V1 Variables
	// ------------------------------

	// Metadata
	string public contractURI;

	/*
	 * DO NOT ADD OR REMOVE VARIABLES ABOVE THIS LINE. INSTEAD, CREATE A NEW VERSION SECTION BELOW.
	 * MOVE THIS COMMENT BLOCK TO THE END OF THE LATEST VERSION SECTION PRE-DEPLOYMENT.
	 */

	/// @custom:oz-upgrades-unsafe-allow constructor
	constructor() {
		_disableInitializers();
	}

	//Abstract contract should not have a initialize function
	function __MightyNetERC1155Upgradeable_init(
		string memory baseURI_,
		string memory contractURI_,
		IOperatorFilterRegistry operatorFilterRegistry_
	) internal onlyInitializing {
		__ERC1155_init(
			string(
				abi.encodePacked(
					baseURI_,
					Strings.toHexString(uint160(address(this)), 20),
					"/{id}"
				)
			)
		);
		__ERC1155Pausable_init();
		__Ownable_init();
		__AccessControl_init();
		__ReentrancyGuard_init();
		__OperatorFilterer_init(operatorFilterRegistry_);

		// Set defaults
		_grantRole(DEFAULT_ADMIN_ROLE, msg.sender);

		setContractURI(contractURI_);
	}

	// ------------------------------
	// 			  Minting
	// ------------------------------

	function mint(
		address to,
		uint256 id,
		uint256 amount
	) external virtual nonReentrant whenNotPaused onlyRole(MINTER_ROLE) {
		_mint(to, id, amount, "");
	}

	function mintBatch(
		address to,
		uint256[] memory ids,
		uint256[] memory amounts
	) external override nonReentrant whenNotPaused onlyRole(MINTER_ROLE) {
		_mintBatch(to, ids, amounts, "");
	}

	// ------------------------------
	// 			 Burning
	// ------------------------------

	function burn(
		address from,
		uint256 id,
		uint256 amount
	) external virtual nonReentrant whenNotPaused onlyRole(BURNER_ROLE) {
		_burn(from, id, amount);
	}

	function burnBatch(
		address from,
		uint256[] memory ids,
		uint256[] memory amounts
	) external override nonReentrant whenNotPaused onlyRole(BURNER_ROLE) {
		_burnBatch(from, ids, amounts);
	}

	// ------------------------------
	// 			 Transfers
	// ------------------------------

	function _beforeTokenTransfer(
		address operator,
		address from,
		address to,
		uint256[] memory ids,
		uint256[] memory amounts,
		bytes memory data
	)
		internal
		virtual
		override(ERC1155PausableUpgradeable)
		whenNotPaused
		onlyAllowedOperator
	{
		super._beforeTokenTransfer(operator, from, to, ids, amounts, data);
	}

	function safeTransferFrom(
		address from,
		address to,
		uint256 id,
		uint256 amount
	) public virtual whenNotPaused {
		safeTransferFrom(from, to, id, amount, "");
	}

	function safeTransferFrom(
		address from,
		address to,
		uint256 id,
		uint256 amount,
		bytes memory data
	) public override(ERC1155Upgradeable, IERC1155Upgradeable) whenNotPaused {
		super.safeTransferFrom(from, to, id, amount, data);
	}

	function safeBatchTransferFrom(
		address from,
		address to,
		uint256[] memory ids,
		uint256[] memory amounts
	) public virtual whenNotPaused {
		safeBatchTransferFrom(from, to, ids, amounts, "");
	}

	function safeBatchTransferFrom(
		address from,
		address to,
		uint256[] memory ids,
		uint256[] memory amounts,
		bytes memory data
	) public override(ERC1155Upgradeable, IERC1155Upgradeable) whenNotPaused {
		super.safeBatchTransferFrom(from, to, ids, amounts, data);
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
		super._setURI(
			string(
				abi.encodePacked(
					baseURI_,
					Strings.toHexString(uint160(address(this)), 20),
					"/{id}"
				)
			)
		);
	}

	function setContractURI(string memory contractURI_)
		public
		virtual
		onlyRole(DEFAULT_ADMIN_ROLE)
	{
		contractURI = string(
			abi.encodePacked(
				contractURI_,
				Strings.toHexString(uint160(address(this)), 20)
			)
		);
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
	// 		   Miscellaneous
	// ------------------------------

	function supportsInterface(bytes4 interfaceId)
		public
		view
		virtual
		override(
			ERC1155Upgradeable,
			AccessControlUpgradeable,
			IERC165Upgradeable
		)
		returns (bool)
	{
		return
			interfaceId == type(IMightyNetERC1155Assets).interfaceId ||
			super.supportsInterface(interfaceId);
	}

	uint256[49] private gap_MightyNetERC1155Upgradeable;
}

