// SPDX-License-Identifier: MIT
import "./IERC721.sol";

pragma solidity 0.8.17;

interface INft is IERC721{
	function mint(address to, uint tokenId) external;
	function burn(uint tokenId) external;
}
