// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./PausableUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./AccessControlUpgradeable.sol";

import "./IMightyNetERC1155Assets.sol";
import "./IMightyNetERC721Assets.sol";
import { IRestrictedRegistry } from "./IRestrictedRegistry.sol";

error UnregisteredTokenContract(address contractAddress);
error InvalidTokenContract(address contractAddress);
error InvalidTokenContractType();
error InvalidAddress(address address_);
error NotOwnerOfToken(address contractAddress);
error InsufficientTokens(address contractAddress, uint256 tokenId);
error InsufficientBalance(uint256 balance, uint256 required);
error ValueLowerThanMinimumFee(uint256 value, uint256 minimum);
error TokenSendRestricted(address contractAddress, uint256 tokenId);

contract MightyNetTerminal is
	PausableUpgradeable,
	ReentrancyGuardUpgradeable,
	AccessControlUpgradeable
{
	event ReceiveRequestedERC721(
		address contractAddress,
		address owner,
		uint256 feePaid,
		uint256[] assetIds
	);

	event ReceiveRequestedERC1155(
		address contractAddress,
		address owner,
		uint256 feePaid,
		uint256[] assetIds,
		uint256[] assetQuantities
	);

	event ReceivedERC721(
		address contractAddress,
		address owner,
		uint256[] assetIds,
		string requestEventId
	);

	event ReceivedERC1155(
		address contractAddress,
		address owner,
		uint256[] assetIds,
		uint256[] assetQuantities,
		string requestEventId
	);

	event SentERC721(
		address contractAddress,
		address owner,
		uint256[] assetIds
	);

	event SentERC1155(
		address contractAddress,
		address owner,
		uint256[] assetIds,
		uint256[] assetQuantities
	);

	bytes32 public constant RECEIVE_EXECUTOR_ROLE =
		keccak256("RECEIVE_EXECUTOR_ROLE");

	uint256 public constant UNREGISTERED_CONTRACT_TYPE = 0;
	uint256 public constant ERC1155_CONTRACT_TYPE = 1;
	uint256 public constant ERC721_CONTRACT_TYPE = 2;

	// ------------------------------
	// 			V1 Variables
	// ------------------------------

	IRestrictedRegistry public restrictedRegistry;

	mapping(address => uint256) public tokenContracts;
	mapping(address => mapping(uint256 => bool)) public tokenSendRestrictions;

	address payable public feesVault;

	uint256 public minimumFee;

	/*
	 * DO NOT ADD OR REMOVE VARIABLES ABOVE THIS LINE. INSTEAD, CREATE A NEW VERSION SECTION BELOW.
	 * MOVE THIS COMMENT BLOCK TO THE END OF THE LATEST VERSION SECTION PRE-DEPLOYMENT.
	 */

	/// @custom:oz-upgrades-unsafe-allow constructor
	constructor() {
		_disableInitializers();
	}

	function initialize(
		IRestrictedRegistry restrictedRegistry_,
		uint256 minimumFeeAmount_,
		address payable feesVault_
	) public initializer {
		__Pausable_init();
		__ReentrancyGuard_init();
		__AccessControl_init();

		// Set defaults
		_grantRole(DEFAULT_ADMIN_ROLE, msg.sender);

		feesVault = feesVault_;
		minimumFee = minimumFeeAmount_;

		_setRestrictedRegistry(restrictedRegistry_);
	}

	// ------------------------------
	// 		   Receive Request
	// ------------------------------

	function requestReceiveFromGameERC721(
		address contractAddress,
		uint256[] calldata tokenIds
	)
		external
		payable
		hasFeesVault
		valueAboveMinimumFee
		nonReentrant
		whenNotPaused
		isRegisteredContract(contractAddress, ERC721_CONTRACT_TYPE)
	{
		payable(feesVault).transfer(msg.value);

		emit ReceiveRequestedERC721(
			contractAddress,
			msg.sender,
			msg.value,
			tokenIds
		);
	}

	function requestReceiveFromGameERC1155(
		address contractAddress,
		uint256[] calldata tokenIds,
		uint256[] calldata quantities
	)
		external
		payable
		hasFeesVault
		valueAboveMinimumFee
		nonReentrant
		whenNotPaused
		isRegisteredContract(contractAddress, ERC1155_CONTRACT_TYPE)
	{
		payable(feesVault).transfer(msg.value);

		emit ReceiveRequestedERC1155(
			contractAddress,
			msg.sender,
			msg.value,
			tokenIds,
			quantities
		);
	}

	// ------------------------------
	// 			  Receive
	// ------------------------------

	function receiveFromGameERC721(
		address contractAddress,
		address tokenOwner,
		uint256[] calldata tokenIds,
		string calldata requestEventId
	)
		external
		nonReentrant
		whenNotPaused
		onlyRole(RECEIVE_EXECUTOR_ROLE)
		isRegisteredContract(contractAddress, ERC721_CONTRACT_TYPE)
	{
		IMightyNetERC721Assets tokenContract = IMightyNetERC721Assets(
			contractAddress
		);

		uint256[] memory unrestrictArray = new uint256[](1);

		for (uint256 i = 0; i < tokenIds.length; ++i) {
			if (tokenContract.exists(tokenIds[i])) {
				unrestrictArray[0] = tokenIds[i];
				restrictedRegistry.unrestrict(contractAddress, unrestrictArray);
			} else {
				tokenContract.mint(tokenOwner, tokenIds[i]);
			}
		}

		emit ReceivedERC721(
			contractAddress,
			tokenOwner,
			tokenIds,
			requestEventId
		);
	}

	function receiveFromGameERC1155(
		address contractAddress,
		address tokenOwner,
		uint256[] calldata tokenIds,
		uint256[] calldata quantities,
		string calldata requestEventId
	)
		external
		nonReentrant
		whenNotPaused
		onlyRole(RECEIVE_EXECUTOR_ROLE)
		isRegisteredContract(contractAddress, ERC1155_CONTRACT_TYPE)
	{
		IMightyNetERC1155Assets(contractAddress).mintBatch(
			tokenOwner,
			tokenIds,
			quantities
		);

		emit ReceivedERC1155(
			contractAddress,
			tokenOwner,
			tokenIds,
			quantities,
			requestEventId
		);
	}

	// ------------------------------
	// 			   Send
	// ------------------------------

	function sendToGameERC721(
		address contractAddress,
		uint256[] calldata tokenIds
	)
		external
		nonReentrant
		whenNotPaused
		isRegisteredContract(contractAddress, ERC721_CONTRACT_TYPE)
		areTokensSendUnrestricted(contractAddress, tokenIds)
	{
		IMightyNetERC721Assets interfaceContract = IMightyNetERC721Assets(
			contractAddress
		);
		for (uint256 i = 0; i < tokenIds.length; ++i) {
			if (interfaceContract.ownerOf(tokenIds[i]) != msg.sender) {
				revert NotOwnerOfToken(msg.sender);
			}
		}
		restrictedRegistry.restrict(contractAddress, tokenIds);

		emit SentERC721(contractAddress, msg.sender, tokenIds);
	}

	function sendToGameERC1155(
		address contractAddress,
		uint256[] calldata tokenIds,
		uint256[] calldata amounts
	)
		external
		nonReentrant
		whenNotPaused
		isRegisteredContract(contractAddress, ERC1155_CONTRACT_TYPE)
		areTokensSendUnrestricted(contractAddress, tokenIds)
	{
		IMightyNetERC1155Assets interfaceContract = IMightyNetERC1155Assets(
			contractAddress
		);
		for (uint256 i = 0; i < tokenIds.length; ++i) {
			if (
				interfaceContract.balanceOf(msg.sender, tokenIds[i]) <
				amounts[i]
			) {
				revert InsufficientTokens(msg.sender, tokenIds[i]);
			}
		}
		interfaceContract.burnBatch(msg.sender, tokenIds, amounts);

		emit SentERC1155(contractAddress, msg.sender, tokenIds, amounts);
	}

	// ------------------------------
	// 			   Setter
	// ------------------------------

	function setTokenContracts(address contractAddress, uint256 contractType)
		external
		isValidContractAddress(contractAddress, contractType)
		onlyRole(DEFAULT_ADMIN_ROLE)
	{
		tokenContracts[contractAddress] = contractType;
	}

	function setFeesVaultAddress(address payable vault_)
		external
		onlyRole(DEFAULT_ADMIN_ROLE)
	{
		feesVault = vault_;
	}

	function setMinimumFee(uint256 amount_)
		external
		onlyRole(DEFAULT_ADMIN_ROLE)
	{
		minimumFee = amount_;
	}

	function setTokenSendRestriction(
		address contractAddress,
		uint256 tokenId,
		bool isRestricted
	) external onlyRole(DEFAULT_ADMIN_ROLE) {
		tokenSendRestrictions[contractAddress][tokenId] = isRestricted;
	}

	// ------------------------------
	// 			   Admin
	// ------------------------------

	function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
		_pause();
	}

	function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
		_unpause();
	}

	// ------------------------------
	// 			  Queries
	// ------------------------------

	function isTokenSendRestricted(address contractAddress, uint256 tokenId)
		external
		view
		returns (bool)
	{
		return tokenSendRestrictions[contractAddress][tokenId];
	}

	// ------------------------------
	// 			  Modifiers
	// ------------------------------

	modifier isValidContractAddress(
		address contractAddress,
		uint256 contractType
	) {
		if (contractAddress.code.length == 0) {
			revert InvalidTokenContract(contractAddress);
		}

		if ((contractType > ERC721_CONTRACT_TYPE)) {
			revert InvalidTokenContractType();
		} else if (contractType == ERC721_CONTRACT_TYPE) {
			if (
				!IMightyNetERC721Assets(contractAddress).supportsInterface(
					type(IMightyNetERC721Assets).interfaceId
				)
			) {
				revert InvalidTokenContractType();
			}
		} else if (contractType == ERC1155_CONTRACT_TYPE) {
			if (
				!IMightyNetERC1155Assets(contractAddress).supportsInterface(
					type(IMightyNetERC1155Assets).interfaceId
				)
			) {
				revert InvalidTokenContractType();
			}
		}

		_;
	}

	modifier isRegisteredContract(
		address contractAddress,
		uint256 contractType
	) {
		if ((tokenContracts[contractAddress] != contractType)) {
			revert UnregisteredTokenContract(contractAddress);
		}
		_;
	}

	modifier valueAboveMinimumFee() {
		if (msg.value < minimumFee) {
			revert ValueLowerThanMinimumFee(msg.value, minimumFee);
		}
		_;
	}

	modifier hasFeesVault() {
		if (feesVault == address(0)) {
			revert InvalidAddress(feesVault);
		}
		_;
	}

	modifier areTokensSendUnrestricted(
		address contractAddress,
		uint256[] calldata tokenIds
	) {
		for (uint256 i = 0; i < tokenIds.length; i++) {
			if (tokenSendRestrictions[contractAddress][tokenIds[i]]) {
				revert TokenSendRestricted(contractAddress, tokenIds[i]);
			}
		}
		_;
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
}

