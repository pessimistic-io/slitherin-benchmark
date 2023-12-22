// SPDX-License-Identifier: MIT
pragma solidity =0.8.15;

import "./MarketWithoutProtection.sol";
import "./MarketCollateralised.sol";
import "./Market.sol";

contract MarketCollateralisedWithoutProtection is MarketCollateralised {

    constructor(
        IVault vault,
        uint8 fee,
        uint8 timeoutDays,
        address oracle,
        string memory baseMetadataURI
    ) Market(vault, fee, timeoutDays, oracle, baseMetadataURI) {
    }

    function _getAdjustedOdds(
		uint256 /*wager*/,
		uint256 odds,
		uint256 /*pool*/
	) internal pure override returns (uint256) {
		return odds;
	}

}
