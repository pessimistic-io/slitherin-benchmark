// SPDX-License-Identifier: BUSDL-1.1
pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

import {IERC20} from "./common_Imports.sol";
import {SafeMath} from "./libraries_Imports.sol";
import {ImmutableAssetAllocation} from "./tvl_Imports.sol";

import {     IStableSwap,     ILiquidityGauge } from "./interfaces_Imports.sol";

import {     CurveAllocationBase } from "./curve_common_Imports.sol";

import {Curve3poolConstants} from "./metapool_Constants.sol";

contract Curve3poolAllocation is
    CurveAllocationBase,
    ImmutableAssetAllocation,
    Curve3poolConstants
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
                IStableSwap(STABLE_SWAP_ADDRESS),
                ILiquidityGauge(LIQUIDITY_GAUGE_ADDRESS),
                IERC20(LP_TOKEN_ADDRESS),
                uint256(tokenIndex)
            );
    }

    function _getTokenData()
        internal
        pure
        override
        returns (TokenData[] memory)
    {
        TokenData[] memory tokens = new TokenData[](3);
        tokens[0] = TokenData(DAI_ADDRESS, "DAI", 18);
        tokens[1] = TokenData(USDC_ADDRESS, "USDC", 6);
        tokens[2] = TokenData(USDT_ADDRESS, "USDT", 6);
        return tokens;
    }
}

