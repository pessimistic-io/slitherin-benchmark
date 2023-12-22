// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IPriceStrategy {
	function checkPrice(bytes memory priceInfo_) external view returns (bool);
	function getPrice(bytes memory priceInfo_) external view returns (uint256);
}
