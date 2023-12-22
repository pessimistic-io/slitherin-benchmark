// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {Governable} from "./Governable.sol";
import {jTokensOracle} from "./jTokensOracle.sol";
import {IERC20} from "./IERC20.sol";
import {IPrice} from "./IPrice.sol";

contract jUsdcOracle is Governable, jTokensOracle {
    IPrice public clOracle = IPrice(0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3);
    uint256 private constant BASIS = 1e12;
    uint256 private constant DECIMALS = 1e8;

    constructor(address _asset, uint128 _min, uint64 _collected)
        jTokensOracle(_asset, _min, _collected)
        Governable(msg.sender)
    {}

    function _supplyPrice() internal view override returns (uint64) {
        uint256 ratio = viewer.getUSDCRatio(1e18) * BASIS; // 18 decimals
        (, int256 usdcPrice,,,) = clOracle.latestRoundData(); // 8 decimals

        return uint64((ratio * uint256(usdcPrice)) / DECIMALS); // 18 decimals
    }
}

