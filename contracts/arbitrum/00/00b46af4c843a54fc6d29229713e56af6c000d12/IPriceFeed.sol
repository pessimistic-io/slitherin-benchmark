// SPDX-License-Identifier: MIT

pragma solidity ^0.8.14;

interface IPriceFeed {

	struct RegisteredOracle {
		address oracle;
		bool isRegistered;
	}

	event RegisteredNewOracle(
		address token,
		address oracle
	);

	// --- Function ---
	function addOracle(
		address _token,
		address _oracle
	) external;

	function fetchPrice(address _asset) external returns (uint256);

	function getDirectPrice(address _asset) external view returns (uint256);

}

