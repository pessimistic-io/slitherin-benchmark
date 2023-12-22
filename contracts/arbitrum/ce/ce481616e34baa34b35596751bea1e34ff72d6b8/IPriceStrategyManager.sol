// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IPriceStrategyManager {
	function getPrice(uint8 priceType_, bytes memory priceInfo_) external view returns (uint256);
	function checkPrice(uint8 priceType_, bytes memory priceInfo_) external view returns (bool);
}
