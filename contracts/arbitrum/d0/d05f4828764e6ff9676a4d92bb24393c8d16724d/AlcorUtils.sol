// SPDX-License-Identifier: None
pragma solidity ^0.8.18;

import {FullMath} from "./FullMath.sol";
import {ERC20} from "./ERC20.sol";

import {IUniswapV3Pool} from "./IUniswapV3Pool.sol";

library AlcorUtils {
    using FullMath for uint256;

    function sqrtPriceX96ToUint(
        uint160 sqrtPriceX96,
        int16 decimalsTokensDelta
    ) internal pure returns (uint256) {
        uint256 numerator1 = uint256(sqrtPriceX96) * uint256(sqrtPriceX96);
        uint256 numerator2;
        if (decimalsTokensDelta > 0) {
            numerator2 = 10 ** uint16(decimalsTokensDelta) * 1e18;
        } else {
            numerator2 = 1e18 / (10 ** uint16(-decimalsTokensDelta));
        }
        return FullMath.mulDiv(1 << 192, numerator2, numerator1);
    }

    function getDeltaDecimalsToken1Token0(
        IUniswapV3Pool uniswapV3Pool
    ) internal view returns (int16) {
        return
            int8(ERC20(address(uniswapV3Pool.token1())).decimals()) -
            int8(ERC20(address(uniswapV3Pool.token0())).decimals());
    }

    function getTwap(
        IUniswapV3Pool realUniswapV3Pool,
        uint32 _twapDuration
    ) internal view returns (int24) {
        uint32[] memory secondsAgo = new uint32[](2);
        secondsAgo[0] = _twapDuration;
        secondsAgo[1] = 0;

        (int56[] memory tickCumulatives, ) = realUniswapV3Pool.observe(
            secondsAgo
        );
        return
            int24(
                (tickCumulatives[1] - tickCumulatives[0]) / int32(_twapDuration)
            );
    }
}

