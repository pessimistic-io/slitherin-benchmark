// SPDX-License-Identifier: MIT
pragma solidity =0.8.15;

import "./MarketCollateralised.sol";
import "./Market.sol";

contract MarketCollateralisedLinear is MarketCollateralised {

    constructor(
        IVault vault,
        uint8 fee,
        uint8 timeoutDays,
        address oracle,
		string memory baseMetadataURI
	) Market(vault, fee, timeoutDays, oracle, baseMetadataURI) {
    }
}
