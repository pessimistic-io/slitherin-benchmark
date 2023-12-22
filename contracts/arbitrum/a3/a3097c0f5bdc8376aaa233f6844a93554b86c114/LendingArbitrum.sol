// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {CompoundV3USDCArbitrum} from "./CompoundV3USDCArbitrum.sol";

contract LendingArbitrum is CompoundV3USDCArbitrum {
    function _postInit() internal override(CompoundV3USDCArbitrum) {
        CompoundV3USDCArbitrum._postInit();
    }
}

