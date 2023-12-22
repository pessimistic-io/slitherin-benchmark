// SPDX-License-Identifier: MIT

pragma solidity ^0.8.14;
import "./IOracle.sol";
import "./Ownable.sol";


contract OracleSimpleTest is Ownable, IOracle {

	uint256 public _assetPrice;

	// Use to convert a price answer to an 18-digit precision uint

	constructor() {}


	function getDirectPrice() external view returns (uint256 _priceAssetInUSD) {
		return _assetPrice;
	}

	function fetchPrice() external override returns (uint256) {
		return _assetPrice;
	}

	// Manual external price setter.
	function setPrice(uint256 price) external onlyOwner returns (bool) {
		_assetPrice = price;
		return true;
	}
}

