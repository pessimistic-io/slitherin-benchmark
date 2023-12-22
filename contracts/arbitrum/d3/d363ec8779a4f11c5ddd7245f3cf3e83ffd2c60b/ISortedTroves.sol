// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface ISortedTroves {
	function getLast(address _asset) external view returns (address);
}


