// SPDX-License-Identifier: BUSDL-1.1
pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

import {     MetaPoolAllocationBaseV3 } from "./interfaces_Imports.sol";

import {CurveUstWormholeConstants} from "./metapool_Constants.sol";

contract CurveUstWormholeAllocation is
    MetaPoolAllocationBaseV3,
    CurveUstWormholeConstants
{
    function balanceOf(address account, uint8 tokenIndex)
        public
        view
        override
        returns (uint256)
    {
        return
            super.getUnderlyerBalance(
                account,
                META_POOL,
                LIQUIDITY_GAUGE,
                LP_TOKEN,
                uint256(tokenIndex)
            );
    }

    function _getTokenData()
        internal
        pure
        override
        returns (TokenData[] memory)
    {
        return _getBasePoolTokenData();
    }
}

