// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./SafeERC20.sol";

import "./ITreasury.sol";
import "./ITrading.sol";
import "./IRouter.sol";

contract Router {

	using SafeERC20 for IERC20; 

	// Contract dependencies
	address public owner;
	address public trading;
	address public oracle;
	address public tokenPool;
	address public treasury;
	address public darkOracle;

	address[] public currencies;

	mapping(address => uint8) decimals;

	mapping(address => address) pools; // currency => contract
	
	mapping(address => uint256) private poolShare; // currency (eth, usdc, etc.) => bps
	mapping(address => uint256) private tokenShare; // currency => bps

	mapping(address => address) poolRewards; // currency => contract
	mapping(address => address) tokenRewards; // currency => contract

	constructor() {
		owner = msg.sender;
	}

	function isSupportedCurrency(address currency) external view returns(bool) {
		return currency != address(0) && pools[currency] != address(0);
	}

	function currenciesLength() external view returns(uint256) {
		return currencies.length;
	}

	function getPool(address currency) external view returns(address) {
		return pools[currency];
	}

	function getPoolShare(address currency) external view returns(uint256) {
		return poolShare[currency];
	}

	function getTokenShare(address currency) external view returns(uint256) {
		return tokenShare[currency];
	}

	function getPoolRewards(address currency) external view returns(address) {
		return poolRewards[currency];
	}

	function getTokenRewards(address currency) external view returns(address) {
		return tokenRewards[currency];
	}

	function getDecimals(address currency) external view returns(uint8) {
		if (currency == address(0)) return 18;
		if (decimals[currency] > 0) return decimals[currency];
		if (IERC20(currency).decimals() > 0) return IERC20(currency).decimals();
		return 18;
	}

	// Setters

	function setCurrencies(address[] calldata _currencies) external onlyOwner {
		currencies = _currencies;
	}

	function setDecimals(address currency, uint8 _decimals) external onlyOwner {
		decimals[currency] = _decimals;
	}

	function setContracts(
		address _treasury,
		address _trading,
		address _tokenPool,
		address _oracle,
		address _darkOracle
	) external onlyOwner {
		treasury = _treasury;
		trading = _trading;
		tokenPool = _tokenPool;
		oracle = _oracle;
		darkOracle = _darkOracle;
	}

	function setPool(address currency, address _contract) external onlyOwner {
		pools[currency] = _contract;
	}

	function setPoolShare(address currency, uint256 share) external onlyOwner {
		poolShare[currency] = share;
	}
	function setTokenShare(address currency, uint256 share) external onlyOwner {
		tokenShare[currency] = share;
	}

	function setPoolRewards(address currency, address _contract) external onlyOwner {
		poolRewards[currency] = _contract;
	}

	function setTokenRewards(address currency, address _contract) external onlyOwner {
		tokenRewards[currency] = _contract;
	}

	function setOwner(address newOwner) external onlyOwner {
		owner = newOwner;
	}

	// Modifiers

	modifier onlyOwner() {
		require(msg.sender == owner, "!owner");
		_;
	}

}
