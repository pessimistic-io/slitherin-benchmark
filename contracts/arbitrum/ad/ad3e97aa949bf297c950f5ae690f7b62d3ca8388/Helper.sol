// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.5.0 <0.8.14;
pragma abicoder v2;

import { SafeMath } from "./SafeMath.sol";
import { IUniswapV3Pool } from "./IUniswapV3Pool.sol";
import { TickMath } from "./TickMath.sol";
import { FullMath } from "./FullMath.sol";
import { OracleLibrary } from "./OracleLibrary.sol";

library Helper {
  using SafeMath for uint256;

  function sqrtPriceX96(IUniswapV3Pool pool) internal view returns (uint160 _sqrtPriceX96) {
    (_sqrtPriceX96, , , , , , ) = pool.slot0();
  }

  function oracleSqrtPricex96(IUniswapV3Pool pool, uint32 elapsedSeconds) internal view returns (uint160) {
    (int24 arithmeticMeanTick, ) = OracleLibrary.consult(address(pool), elapsedSeconds);
    return TickMath.getSqrtRatioAtTick(arithmeticMeanTick);
  }

  function sqrtPriceX96ToUint(uint160 _sqrtPriceX96, uint8 decimalsToken0) internal pure returns (uint256) {
    uint256 numerator1 = uint256(_sqrtPriceX96) * uint256(_sqrtPriceX96);
    uint256 numerator2 = 10 ** decimalsToken0;
    return FullMath.mulDiv(numerator1, numerator2, 1 << 192);
  }

  function convert0ToToken1(
    uint160 _sqrtPriceX96,
    uint256 amount0,
    uint8 decimalsToken0
  ) internal pure returns (uint256 amount0ConvertedToToken1) {
    uint256 price = sqrtPriceX96ToUint(_sqrtPriceX96, decimalsToken0);
    amount0ConvertedToToken1 = amount0.mul(price).div(10 ** decimalsToken0);
  }

  function convert1ToToken0(
    uint160 _sqrtPriceX96,
    uint256 amount1,
    uint8 decimalsToken0
  ) internal pure returns (uint256 amount1ConvertedToToken0) {
    uint256 price = sqrtPriceX96ToUint(_sqrtPriceX96, decimalsToken0);
    if (price == 0) return 0;
    amount1ConvertedToToken0 = amount1.mul(10 ** decimalsToken0).div(price);
  }
}

