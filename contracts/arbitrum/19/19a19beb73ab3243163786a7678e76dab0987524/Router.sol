// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./SafeERC20.sol";

import "./ITreasury.sol";
import "./ITrading.sol";
import "./IRouter.sol";

contract Router {

	//sets up everything and is essentially a middleman for information using its (builtin) getters

	using SafeERC20 for IERC20; 

	// Contract dependencies
	//these addresses are called by the other contracts for information	
	address public owner;
	address public trading;
	address public oracle;
	address public safxPool;
	address public treasury;
	address public darkOracle;
	address public rewards;
	address public pool;
//	address public mining;
	//address public oracleOracle;

	address[] public currencies;

	mapping(address => uint8) decimals;

	mapping(address => address) pools; // currency => contract
	
	mapping(address => uint256) private poolShare; // currency (eth, usdc, etc.) => bps
	mapping(address => uint256) private safxShare; // currency => bps

	mapping(address => address) poolRewards; // currency => contract
	mapping(address => address) safxRewards; // currency => contract

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

	function getSafxShare(address currency) external view returns(uint256) {
		return safxShare[currency];
	}

	function getPoolRewards(address currency) external view returns(address) {
		return poolRewards[currency];
	}

	function getSafxRewards(address currency) external view returns(address) {
		return safxRewards[currency];
	}

/* 	function setMining(address _mining) external onlyOwner {
		mining = _mining;
	} */

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
		address _safxPool,
		address _oracle,
		address _darkOracle
		//address _oracleOracle,
		//address _mining
	) external onlyOwner {
		treasury = _treasury;
		trading = _trading;
		safxPool = _safxPool;
		oracle = _oracle;
		darkOracle = _darkOracle;
		//oracleOracle = _oracleOracle;
		//mining = _mining;
	}

	function setPool(address currency, address _contract) external onlyOwner {
		pools[currency] = _contract;
	}

	function setPoolShare(address currency, uint256 share) external onlyOwner {
		poolShare[currency] = share;
	}
	function setSafxShare(address currency, uint256 share) external onlyOwner {
		safxShare[currency] = share;
	}

	function setPoolRewards(address currency, address _contract) external onlyOwner {
		poolRewards[currency] = _contract;
	}

	function setSafxRewards(address currency, address _contract) external onlyOwner {
		safxRewards[currency] = _contract;
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
