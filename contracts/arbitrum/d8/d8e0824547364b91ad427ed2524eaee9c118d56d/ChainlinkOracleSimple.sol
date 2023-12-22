// SPDX-License-Identifier: MIT

pragma solidity ^0.8.14;
import "./IOracle.sol";
import "./AggregatorV3Interface.sol";


contract ChainlinkOracleSimple is IOracle {

	AggregatorV3Interface public immutable toUSD;
	AggregatorV3Interface public immutable toETH;

	// Use to convert a price answer to an 18-digit precision uint
	uint256 public constant TARGET_DECIMAL_1E18 = 1e18;

	constructor(address _toETH, address _toUSD) {
		require(_toETH != address(0), "Invalid chainlink address");
		require(_toUSD != address(0), "Invalid chainlink address");
		toUSD = AggregatorV3Interface(_toUSD);
		toETH = AggregatorV3Interface(_toETH);
	}


	function getDirectPrice() external view returns (uint256 _priceAssetInUSD) {
		return _getChainlinkPrice();
	}

	function fetchPrice() external override returns (uint256) {
		return _getChainlinkPrice();
	}

	function _getChainlinkPrice() internal view returns (uint256) {
		(, int256 _priceIntETH, , uint256 _updatedAtETH, ) = toETH.latestRoundData();
		(, int256 _priceIntUSD, , uint256 _updatedAtUSD, ) = toUSD.latestRoundData();
		require(
			_updatedAtETH > block.timestamp - 24 hours &&
			_updatedAtUSD > block.timestamp - 24 hours,
			"Chainlink price outdated"
		);
		return uint256(_priceIntETH) * uint256(_priceIntUSD) * TARGET_DECIMAL_1E18 / 1e26;
	}
}

