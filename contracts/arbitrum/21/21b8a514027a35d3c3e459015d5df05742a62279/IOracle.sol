// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

interface IOracle {
	function fetchPrice() external returns (uint256);
    function getDirectPrice() external view returns (uint256);
}

