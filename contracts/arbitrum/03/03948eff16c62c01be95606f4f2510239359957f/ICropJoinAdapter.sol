// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface ICropJoinAdapter {
	event Join(uint256 val);
	event Exit(uint256 val);
	event Flee();
	event Tack(address indexed src, address indexed dst, uint256 wad);

	function shareOf(address owner) external view returns (uint256);
}


