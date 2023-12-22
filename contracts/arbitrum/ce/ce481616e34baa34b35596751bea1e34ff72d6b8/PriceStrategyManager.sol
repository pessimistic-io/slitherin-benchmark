// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./AdminControl.sol";
import "./FixedPriceStrategy.sol";
import "./IPriceStrategy.sol";
import "./IPriceStrategyManager.sol";

contract PriceStrategyManager is IPriceStrategyManager, AdminControl {
	mapping(uint8 => address) public priceStrategies;
	
	function initialize() external initializer {
		__AdminControl_init_unchained(_msgSender());
		priceStrategies[1] = address(new FixedPriceStrategy());
	}

	function getPrice(uint8 priceType_, bytes memory priceInfo_) public view override returns (uint256) {
		require(priceType_ > 0, "PriceStrategyManager: priceType_ must be greater than 0");
		require(priceStrategies[priceType_] != address(0), "PriceStrategyManager: priceType not found");
		return IPriceStrategy(priceStrategies[priceType_]).getPrice(priceInfo_);
	}

	function checkPrice(uint8 priceType_, bytes memory priceInfo_) public view override returns (bool) {
		require(priceType_ > 0, "PriceStrategyManager: priceType_ must be greater than 0");
		require(priceStrategies[priceType_] != address(0), "PriceStrategyManager: priceType not found");
		return IPriceStrategy(priceStrategies[priceType_]).checkPrice(priceInfo_);
	}
}
