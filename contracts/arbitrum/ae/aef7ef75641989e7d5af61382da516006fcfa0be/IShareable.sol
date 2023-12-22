// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface IShareable {
	event ShareUpdated(uint256 val);
	event Flee();
	event Tack(address indexed src, address indexed dst, uint256 wad);

	function netAssetsPerShareWAD() external view returns (uint256);

	function getCropsOf(uint256 _lockId) external view returns (uint256);

	function getShareOf(uint256 _lockId) external view returns (uint256);
}


