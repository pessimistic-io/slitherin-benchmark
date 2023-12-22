// SPDX-License-Identifier: MIT
pragma solidity =0.8.15;

import "./Market.sol";
import "./OddsLib.sol";

abstract contract MarketWithoutProtection is Market {

	function _getAdjustedOdds(
		uint256 /*wager*/,
		uint256 odds,
		uint256 /*pool*/
	) internal pure override returns (uint256) {
		return odds;
	}
}
