// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./PausableUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./AccessControlUpgradeable.sol";

error NotEnoughSupply(uint256 shopItemId);
error InvalidAddress(address address_);
error InvalidShopItemId(uint256 shopItemId);
error InvalidSupply();
error IncorrectEtherValue(uint256 expectedValue);
error InsufficientBalance(uint256 balance, uint256 required);

contract MightyNetShop is
	PausableUpgradeable,
	ReentrancyGuardUpgradeable,
	AccessControlUpgradeable
{
	event ItemBought(
		uint256 shopItemId,
		string staticItemId,
		uint256 boughtSupply,
		address buyer
	);

	event ShopItemAdded(uint256 shopItemId, ShopItem shopItem);
	event ShopItemDeleted(uint256 shopItemId);
	event ShopItemUpdate(uint256 shopItemId, ShopItem shopItem);

	// ------------------------------
	// 			V1 Variables
	// ------------------------------

	struct ShopItem {
		string staticItemId;
		uint256 supply;
		uint256 price;
		bool isEnabled;
	}

	mapping(uint256 => ShopItem) public shopItems;

	uint256 public nextShopItemId;
	address payable public vault;

	/*
	 * DO NOT ADD OR REMOVE VARIABLES ABOVE THIS LINE. INSTEAD, CREATE A NEW VERSION SECTION BELOW.
	 * MOVE THIS COMMENT BLOCK TO THE END OF THE LATEST VERSION SECTION PRE-DEPLOYMENT.
	 */

	/// @custom:oz-upgrades-unsafe-allow constructor
	constructor() {
		_disableInitializers();
	}

	function initialize(address payable vault_) public initializer {
		__Pausable_init();
		__ReentrancyGuard_init();
		__AccessControl_init();

		_grantRole(DEFAULT_ADMIN_ROLE, msg.sender);

		vault = vault_;
		nextShopItemId = 0;
	}

	// ------------------------------
	// 			Purchasing
	// ------------------------------

	function purchaseItem(uint256 shopItemId, uint256 supplyToBuy)
		external
		payable
		nonReentrant
		whenNotPaused
		isValidShopItemId(shopItemId)
	{
		if (supplyToBuy <= 0) {
			revert InvalidSupply();
		}

		ShopItem memory shopItem = shopItems[shopItemId];

		if (supplyToBuy > shopItem.supply) {
			revert NotEnoughSupply(shopItemId);
		}

		if (
			bytes(shopItem.staticItemId).length == 0 ||
			shopItem.isEnabled == false ||
			shopItem.price == 0
		) {
			revert InvalidShopItemId(shopItemId);
		}

		uint256 expectedValue = shopItem.price * supplyToBuy;

		if (msg.value != expectedValue) {
			revert IncorrectEtherValue(expectedValue);
		}

		shopItems[shopItemId].supply -= supplyToBuy;

		emit ItemBought(
			shopItemId,
			shopItem.staticItemId,
			supplyToBuy,
			msg.sender
		);
	}

	// ------------------------------
	// 			   Setter
	// ------------------------------

	function setVaultAddress(address payable vault_)
		external
		onlyRole(DEFAULT_ADMIN_ROLE)
	{
		vault = vault_;
	}

	// ------------------------------
	// 		Shop Item Admin
	// ------------------------------

	function addShopItem(
		string calldata staticItemId,
		uint256 supply,
		uint256 price,
		bool isEnabled
	) external onlyRole(DEFAULT_ADMIN_ROLE) {
		ShopItem memory shopItem = ShopItem(
			staticItemId,
			supply,
			price,
			isEnabled
		);

		uint256 currentShopId = nextShopItemId++;

		shopItems[currentShopId] = shopItem;

		emit ShopItemAdded(currentShopId, shopItem);
	}

	function deteleShopItem(uint256 shopItemId)
		external
		onlyRole(DEFAULT_ADMIN_ROLE)
		isValidShopItemId(shopItemId)
	{
		shopItems[shopItemId] = ShopItem("", 0, 0, false);

		emit ShopItemDeleted(shopItemId);
	}

	function setShopItemStaticItemId(
		uint256 shopItemId,
		string calldata staticItemId
	) external onlyRole(DEFAULT_ADMIN_ROLE) isValidShopItemId(shopItemId) {
		shopItems[shopItemId].staticItemId = staticItemId;

		emit ShopItemUpdate(shopItemId, shopItems[shopItemId]);
	}

	function addShopItemSupply(uint256 shopItemId, uint256 deltaSupply)
		external
		onlyRole(DEFAULT_ADMIN_ROLE)
		isValidShopItemId(shopItemId)
	{
		shopItems[shopItemId].supply += deltaSupply;

		emit ShopItemUpdate(shopItemId, shopItems[shopItemId]);
	}

	function setShopItemPrice(uint256 shopItemId, uint256 price)
		external
		onlyRole(DEFAULT_ADMIN_ROLE)
		isValidShopItemId(shopItemId)
	{
		shopItems[shopItemId].price = price;

		emit ShopItemUpdate(shopItemId, shopItems[shopItemId]);
	}

	function setShopItemEnable(uint256 shopItemId, bool enable)
		external
		onlyRole(DEFAULT_ADMIN_ROLE)
		isValidShopItemId(shopItemId)
	{
		shopItems[shopItemId].isEnabled = enable;

		emit ShopItemUpdate(shopItemId, shopItems[shopItemId]);
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
	// 			 Withdrawal
	// ------------------------------

	function withdraw(uint256 _amount)
		external
		onlyRole(DEFAULT_ADMIN_ROLE)
		hasVault
	{
		if (address(this).balance < _amount) {
			revert InsufficientBalance(address(this).balance, _amount);
		}

		payable(vault).transfer(_amount);
	}

	function withdrawAll() external onlyRole(DEFAULT_ADMIN_ROLE) hasVault {
		if (address(this).balance < 1) {
			revert InsufficientBalance(address(this).balance, 1);
		}

		payable(vault).transfer(address(this).balance);
	}

	// ------------------------------
	// 			  Modifiers
	// ------------------------------

	modifier hasVault() {
		if (vault == address(0)) {
			revert InvalidAddress(vault);
		}
		_;
	}

	modifier isValidShopItemId(uint256 shopItemId) {
		if (shopItemId >= nextShopItemId) {
			revert InvalidShopItemId(shopItemId);
		}
		_;
	}
}

