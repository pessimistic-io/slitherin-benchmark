// SPDX-License-Identifier: MIT

pragma solidity ^0.8.14;
import "./IPriceFeed.sol";
import "./SafeMath.sol";
import "./Ownable.sol";
/*
 * PriceFeed placeholder for testnet and development. The price is simply set manually and saved in a state
 * variable. The contract does not connect to a live Chainlink price feed.
 */
contract PriceFeedTestnet is Ownable, IPriceFeed {
	using SafeMath for uint256;

	string public constant NAME = "PriceFeedTestnet";

	uint256 private _price = 200 ether;
	uint256 private _index = 1 ether;

	struct MockOracleData {
		address oracle;
		bool registered;
	}

	mapping(address => MockOracleData) public oracles;
	bool public isInitialized = true;
	// --- Functions ---


	function addOracle(
		address _token,
		address _oracle
	) external {
		oracles[_token] = MockOracleData(_oracle, true);
	}


	function fetchPrice(address _asset) external override returns (uint256) {
		// Fire an event just like the mainnet version would.
		// This lets the subgraph rely on events to get the latest price even when developing locally.
		
		return _price;
	}

		function getPrice() external view returns (uint256) {
		// Fire an event just like the mainnet version would.
		// This lets the subgraph rely on events to get the latest price even when developing locally.
		
		return _price;
	}

	function getDirectPrice(address _asset) external view override returns (uint256) {
		// Fire an event just like the mainnet version would.
		// This lets the subgraph rely on events to get the latest price even when developing locally.
		
		return _price;
	}

	// Manual external price setter.
	function setPrice(uint256 price) external returns (bool) {
		_price = price;
		return true;
	}

	function setIndex(uint256 index) external returns (bool) {
		_index = index;
		return true;
	}
}

