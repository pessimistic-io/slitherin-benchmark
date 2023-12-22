// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract FixedPriceStrategy {
	struct FixedPrice {
        uint256 price;
    }

	function getPrice(bytes memory priceInfo_) public pure returns (uint256) {
		FixedPrice memory fixedPrice = abi.decode(priceInfo_, (FixedPrice));
		return fixedPrice.price;
	}

	function checkPrice(bytes memory priceInfo_) public pure returns (bool) {
		FixedPrice memory fixedPrice = abi.decode(priceInfo_, (FixedPrice));
		return fixedPrice.price > 0;
	}
}
