// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface IVatLike {
	function urns(bytes32, address) external view returns (uint256, uint256);

	function gem(bytes32, address) external view returns (uint256);

	function slip(
		bytes32,
		address,
		int256
	) external;
}


