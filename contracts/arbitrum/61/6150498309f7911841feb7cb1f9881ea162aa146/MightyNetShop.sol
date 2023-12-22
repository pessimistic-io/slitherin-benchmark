// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./PausableUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./AccessControlUpgradeable.sol";
import "./IERC20Upgradeable.sol";

error NotEnoughSupply(uint256 shopItemId);
error InvalidAddress(address address_);
error InvalidShopItemId(uint256 shopItemId);
error InvalidSupply();
error IncorrectEtherValue(uint256 expectedValue);
error InsufficientBalance(uint256 balance, uint256 required);
error NotSupportedCurrency(address currencyAddress);

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
	event ShopItemUpdated(uint256 shopItemId, ShopItem shopItem);

	// ------------------------------
	// 			V1 Variables
	// ------------------------------

	struct ShopItem {
		string staticItemId;
		uint256 supply;
		uint256 price;
		bool isEnabled;
		bool isUnlimited;
		address mainCurrencyAddress;
		address[] supportedCurrencies;
	}

	mapping(uint256 => ShopItem) public shopItems;

	uint256 public nextShopItemId;
	address payable public vault;

	// ------------------------------
	// 			V2 Variables
	// ------------------------------

	struct CurrencyExchangeRate {
		uint256 rate;
		uint256 precision;
	}

	mapping(address => mapping(address => CurrencyExchangeRate))
		public currencyToExchangeRates;

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

	function purchaseItem(
		uint256 shopItemId,
		uint256 supplyToBuy,
		address currencyAddress
	)
		external
		payable
		nonReentrant
		whenNotPaused
		isValidShopItemId(shopItemId)
	{
		ShopItem storage shopItem = shopItems[shopItemId];

		if (!shopItem.isUnlimited && supplyToBuy <= 0) {
			revert InvalidSupply();
		}

		if (!shopItem.isUnlimited && supplyToBuy > shopItem.supply) {
			revert NotEnoughSupply(shopItemId);
		}

		if (!shopItem.isEnabled || bytes(shopItem.staticItemId).length == 0) {
			revert InvalidShopItemId(shopItemId);
		}

		uint256 price = _calculateCurrencyPrice(shopItem, currencyAddress);

		uint256 expectedValue = price * supplyToBuy;

		if (currencyAddress == address(0)) {
			if (msg.value != expectedValue) {
				revert IncorrectEtherValue(expectedValue);
			}
		} else {
			if (msg.value != 0) {
				revert IncorrectEtherValue(0);
			}

			IERC20Upgradeable(currencyAddress).transferFrom(
				msg.sender,
				address(this),
				expectedValue
			);
		}

		if (!shopItem.isUnlimited) {
			shopItems[shopItemId].supply -= supplyToBuy;
		}

		emit ItemBought(
			shopItemId,
			shopItem.staticItemId,
			supplyToBuy,
			msg.sender
		);
	}

	function _calculateCurrencyPrice(
		ShopItem storage shopItem,
		address currencyAddress
	) private view returns (uint256) {
		if (shopItem.price == 0) {
			revert NotSupportedCurrency(currencyAddress);
		}

		if (currencyAddress == shopItem.mainCurrencyAddress) {
			return shopItem.price;
		}

		bool isSupportedCurrency = false;

		for (uint256 i = 0; i < shopItem.supportedCurrencies.length; i++) {
			if (shopItem.supportedCurrencies[i] == currencyAddress) {
				isSupportedCurrency = true;

				break;
			}
		}

		if (!isSupportedCurrency) {
			revert NotSupportedCurrency(currencyAddress);
		}

		CurrencyExchangeRate storage exchangeRate = currencyToExchangeRates[
			shopItem.mainCurrencyAddress
		][currencyAddress];

		if (exchangeRate.rate == 0) {
			revert NotSupportedCurrency(currencyAddress);
		}

		return (shopItem.price * exchangeRate.rate) / exchangeRate.precision;
	}

	// ------------------------------
	// 			   Getter
	// ------------------------------

	function getShopItemSupportedCurrencies(uint256 shopItemId)
		external
		view
		isValidShopItemId(shopItemId)
		returns (address[] memory)
	{
		return shopItems[shopItemId].supportedCurrencies;
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
	// 		  Shop Item Admin
	// ------------------------------

	function addShopItem(
		string calldata staticItemId,
		uint256 supply,
		uint256 price,
		bool isEnabled,
		bool isUnlimited,
		address mainCurrencyAddress,
		address[] calldata supportedCurrencies
	) external onlyRole(DEFAULT_ADMIN_ROLE) {
		ShopItem memory shopItem = ShopItem(
			staticItemId,
			supply,
			price,
			isEnabled,
			isUnlimited,
			mainCurrencyAddress,
			supportedCurrencies
		);

		uint256 currentShopId = nextShopItemId++;

		shopItems[currentShopId] = shopItem;

		emit ShopItemAdded(currentShopId, shopItem);
	}

	function deleteShopItem(uint256 shopItemId)
		external
		onlyRole(DEFAULT_ADMIN_ROLE)
		isValidShopItemId(shopItemId)
	{
		delete shopItems[shopItemId];

		emit ShopItemDeleted(shopItemId);
	}

	function setShopItemStaticItemId(
		uint256 shopItemId,
		string calldata staticItemId
	) external onlyRole(DEFAULT_ADMIN_ROLE) isValidShopItemId(shopItemId) {
		shopItems[shopItemId].staticItemId = staticItemId;

		emit ShopItemUpdated(shopItemId, shopItems[shopItemId]);
	}

	function addShopItemSupply(uint256 shopItemId, uint256 deltaSupply)
		external
		onlyRole(DEFAULT_ADMIN_ROLE)
		isValidShopItemId(shopItemId)
	{
		shopItems[shopItemId].supply += deltaSupply;

		emit ShopItemUpdated(shopItemId, shopItems[shopItemId]);
	}

	function setShopItemPrice(uint256 shopItemId, uint256 price)
		external
		onlyRole(DEFAULT_ADMIN_ROLE)
		isValidShopItemId(shopItemId)
	{
		shopItems[shopItemId].price = price;

		emit ShopItemUpdated(shopItemId, shopItems[shopItemId]);
	}

	function setShopItemEnabled(uint256 shopItemId, bool enable)
		external
		onlyRole(DEFAULT_ADMIN_ROLE)
		isValidShopItemId(shopItemId)
	{
		shopItems[shopItemId].isEnabled = enable;

		emit ShopItemUpdated(shopItemId, shopItems[shopItemId]);
	}

	function setShopItemIsUnlimited(uint256 shopItemId, bool isUnlimited)
		external
		onlyRole(DEFAULT_ADMIN_ROLE)
		isValidShopItemId(shopItemId)
	{
		shopItems[shopItemId].isUnlimited = isUnlimited;

		emit ShopItemUpdated(shopItemId, shopItems[shopItemId]);
	}

	function setShopItemMainCurrencyAddress(
		uint256 shopItemId,
		address mainCurrencyAddress
	) external onlyRole(DEFAULT_ADMIN_ROLE) isValidShopItemId(shopItemId) {
		shopItems[shopItemId].mainCurrencyAddress = mainCurrencyAddress;

		emit ShopItemUpdated(shopItemId, shopItems[shopItemId]);
	}

	function setShopItemSupportedCurrencies(
		uint256 shopItemId,
		address[] calldata supportedCurrencies
	) external onlyRole(DEFAULT_ADMIN_ROLE) isValidShopItemId(shopItemId) {
		shopItems[shopItemId].supportedCurrencies = supportedCurrencies;

		emit ShopItemUpdated(shopItemId, shopItems[shopItemId]);
	}

	// ------------------------------
	// 			   Admin
	// ------------------------------

	function setCurrencyExchangeRate(
		address mainCurrencyAddress,
		address currencyAddress,
		uint256 rate,
		uint256 precision
	) external onlyRole(DEFAULT_ADMIN_ROLE) {
		currencyToExchangeRates[mainCurrencyAddress][
			currencyAddress
		] = CurrencyExchangeRate(rate, precision);
	}

	function setCurrenciesExchangeRates(
		address mainCurrencyAddress,
		address[] calldata currencyAddresses,
		uint256[] calldata rates,
		uint256[] calldata precisions
	) external onlyRole(DEFAULT_ADMIN_ROLE) {
		for (
			uint256 currencyIndex = 0;
			currencyIndex < currencyAddresses.length;
			currencyIndex++
		) {
			currencyToExchangeRates[mainCurrencyAddress][
				currencyAddresses[currencyIndex]
			] = CurrencyExchangeRate(
				rates[currencyIndex],
				precisions[currencyIndex]
			);
		}
	}

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

	function withdrawToken(uint256 _amount, address _tokenAddress)
		external
		onlyRole(DEFAULT_ADMIN_ROLE)
		hasVault
	{
		IERC20Upgradeable token = IERC20Upgradeable(_tokenAddress);
		if (token.balanceOf(address(this)) < _amount) {
			revert InsufficientBalance(address(this).balance, _amount);
		}

		token.transfer(vault, _amount);
	}

	function withdrawAllToken(address _tokenAddress)
		external
		onlyRole(DEFAULT_ADMIN_ROLE)
		hasVault
	{
		IERC20Upgradeable token = IERC20Upgradeable(_tokenAddress);

		if (token.balanceOf(address(this)) < 1) {
			revert InsufficientBalance(address(this).balance, 1);
		}

		token.transfer(vault, token.balanceOf(address(this)));
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

