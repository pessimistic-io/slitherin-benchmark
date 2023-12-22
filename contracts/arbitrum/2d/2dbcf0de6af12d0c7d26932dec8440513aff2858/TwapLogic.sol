// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.7.6;

import "./IUniswapV3Pool.sol";
import "./TickMath.sol";
import "./FixedPoint96.sol";
import "./FullMath.sol";
import "./ITwapAdapter.sol";

abstract contract TwapLogic is ITwapAdapter {

  function getTwapX96(address uniswapV3Pool, uint32 twapInterval) public view override returns (uint256 priceX96) {
    uint32[] memory secondsAgos = new uint32[](2);
    secondsAgos[0] = twapInterval;
    secondsAgos[1] = 0;
    priceX96 = getTwapX96(uniswapV3Pool, secondsAgos);
  }

  function getTwapX96(address uniswapV3Pool, uint32 twapIntervalFrom, uint32 twapIntervalTo) public view override returns (uint256 priceX96) {
    uint32[] memory secondsAgos = new uint32[](2);
    secondsAgos[0] = twapIntervalFrom;
    secondsAgos[1] = twapIntervalTo;
    priceX96 = getTwapX96(uniswapV3Pool, secondsAgos);
  }

  function getTwapX96(address uniswapV3Pool, uint32[] memory secondsAgos) public view override returns (uint256 priceX96) {    
    uint160 sqrtPriceX96;

    if (
      secondsAgos.length == 0 ||
      (secondsAgos[0] == 0 && secondsAgos[1] == 0)
    ) {
      // return the current price if no secondsAgos are provided
      (sqrtPriceX96, , , , , , ) = IUniswapV3Pool(uniswapV3Pool).slot0();
    } else {
      int32 secondsAgosDiff = int32(secondsAgos[0] - secondsAgos[1]);
      if (secondsAgosDiff <= 0 || secondsAgos.length > 2) {
        revert("Invalid secondsAgos values");
      }
      (int56[] memory tickCumulatives, ) = IUniswapV3Pool(uniswapV3Pool).observe(secondsAgos);
      sqrtPriceX96 = TickMath.getSqrtRatioAtTick(
        int24(uint24(
          uint56(tickCumulatives[1] - tickCumulatives[0]) / uint32(secondsAgosDiff)
        ))
      );
    }

    priceX96 = getPriceX96FromSqrtPriceX96(sqrtPriceX96);
  }

  function getPriceX96FromSqrtPriceX96(uint160 sqrtPriceX96) public pure override returns (uint256 priceX96) {
    return FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, FixedPoint96.Q96);
  }

}

