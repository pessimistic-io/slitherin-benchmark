// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

import {IERC20} from "./common_Imports.sol";
import {SafeMath} from "./libraries_Imports.sol";
import {ImmutableAssetAllocation} from "./tvl_Imports.sol";

import {ConvexFraxUsdcConstants} from "./3pool_Constants.sol";

import {     ConvexAllocationBase } from "./common_Imports.sol";
import {     Curve3poolUnderlyerConstants } from "./3pool_Constants.sol";

contract ConvexFraxUsdcAllocation is
    ConvexAllocationBase,
    ImmutableAssetAllocation,
    ConvexFraxUsdcConstants,
    Curve3poolUnderlyerConstants
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
                STABLE_SWAP_ADDRESS,
                REWARD_CONTRACT_ADDRESS,
                LP_TOKEN_ADDRESS,
                uint256(tokenIndex)
            );
    }

    function _getTokenData()
        internal
        pure
        override
        returns (TokenData[] memory)
    {
        TokenData[] memory tokens = new TokenData[](2);
        tokens[0] = TokenData(FRAX_ADDRESS, "DAI", 18);
        tokens[1] = TokenData(USDC_ADDRESS, "USDC", 6);
        return tokens;
    }
}

