// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0;

interface IOracle {
	function query() external view returns (uint256 price_);

	function token() external view returns (address token_);
}

