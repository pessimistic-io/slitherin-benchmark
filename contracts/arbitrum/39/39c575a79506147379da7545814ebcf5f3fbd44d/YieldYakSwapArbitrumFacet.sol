// SPDX-License-Identifier: BUSL-1.1
// Last deployed from commit: e9e05b6e564514c1bcd1b5e49f5e45250e72bf98;
pragma solidity 0.8.17;

import "./YieldYakSwapFacet.sol";

contract YieldYakSwapArbitrumFacet is YieldYakSwapFacet {
    function YY_ROUTER() internal override pure returns (address) {
        return 0xb32C79a25291265eF240Eb32E9faBbc6DcEE3cE3;
    }
}

