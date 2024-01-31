// SPDX-License-Identifier: BUSDL-1.1
pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

import {IERC20} from "./common_Imports.sol";
import {SafeMath} from "./libraries_Imports.sol";
import {ImmutableAssetAllocation} from "./tvl_Imports.sol";

import {     IStableSwap2,     ILiquidityGauge } from "./interfaces_Imports.sol";

import {     CurveAllocationBase2 } from "./common_Imports.sol";

import {CurveSaaveConstants} from "./3pool_Constants.sol";

contract CurveSaaveAllocation is
    CurveAllocationBase2,
    ImmutableAssetAllocation,
    CurveSaaveConstants
{
    function balanceOf(address account, uint8 tokenIndex)
        public
        view
        override
        returns (uint256)
    {
        // No unwrapping of aTokens are needed, as `balanceOf`
        // automagically reflects the accrued interest and
        // aTokens convert 1:1 to the underlyer.
        return
            super.getUnderlyerBalance(
                account,
                IStableSwap2(STABLE_SWAP_ADDRESS),
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
        TokenData[] memory tokens = new TokenData[](2);
        tokens[0] = TokenData(DAI_ADDRESS, "DAI", 18);
        tokens[1] = TokenData(SUSD_ADDRESS, "sUSD", 18);
        return tokens;
    }
}

