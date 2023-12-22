// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IWINROracleRouter {
	function getPriceMax(address _token) external view returns (uint256 price_);

	function getPriceMin(address _token) external view returns (uint256);

	event TokenAdded(
		address indexed token,
		address indexed priceFeed,
		uint256 priceDecimals,
		bool isStableCoin
	);

	event TokenRemoved(address indexed token);
}

