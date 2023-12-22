// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {Governable} from "./Governable.sol";
import {jTokensOracle} from "./jTokensOracle.sol";
import {IGlpManager} from "./IGlpManager.sol";
import {IERC20} from "./IERC20.sol";

contract jGlpOracle is Governable, jTokensOracle {
    IGlpManager private constant manager = IGlpManager(0x3963FfC9dff443c2A94f21b129D429891E32ec18);
    IERC20 private constant glp = IERC20(0x5402B5F40310bDED796c7D0F3FF6683f5C0cFfdf);
    uint256 private constant BASIS = 1e6;
    uint256 private constant DECIMALS = 1e18;

    constructor(address _asset, uint128 _min, uint64 _collected)
        jTokensOracle(_asset, _min, _collected)
        Governable(msg.sender)
    {}

    function _supplyPrice() internal view override returns (uint64) {
        uint256 jGlpRatio = viewer.getGlpRatioWithoutRetention(1e18);
        uint256 avgAum;
        uint256 jGlpPriceUsd;

        unchecked {
            avgAum = (manager.getAum(false) + manager.getAum(true)) / 2; // 30 decimals
            jGlpPriceUsd = (jGlpRatio * avgAum * BASIS) / (DECIMALS * glp.totalSupply()); //18 decimals
        }

        return uint64(jGlpPriceUsd);
    }
}

