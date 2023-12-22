// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import "./IERC20Metadata.sol";
import "./UniswapV3.sol";


contract PriceOracle {

    function getUniV3Price(address uniswapV3Pool, address baseToken, uint32 twapInterval) external view returns (uint256) {

        IUniswapV3Pool pool = IUniswapV3Pool(uniswapV3Pool);

        uint160 sqrtPriceX96;
        if (twapInterval == 0) {
            // return the current price if twapInterval == 0
            (sqrtPriceX96,,,,,,) = pool.slot0();
        } else {
            uint32[] memory secondsAgos = new uint32[](2);
            secondsAgos[0] = twapInterval; // from (before)
            secondsAgos[1] = 0; // to (now)

            (int56[] memory tickCumulatives,) = pool.observe(secondsAgos);

            // tick(imprecise as it's an integer) to price
            sqrtPriceX96 = TickMath.getSqrtRatioAtTick(int24((tickCumulatives[1] - tickCumulatives[0]) / int32(twapInterval)));
        }

        uint256 token0Decimals = 10 ** IERC20Metadata(pool.token0()).decimals();
        uint256 token1Decimals = 10 ** IERC20Metadata(pool.token1()).decimals();

        uint256 price = FullMath.mulDiv(sqrtPriceX96 * token0Decimals, sqrtPriceX96, 2 ** 192);

        if (baseToken == pool.token0()) {
            return token0Decimals * token1Decimals / price;
        } else {
            return price;
        }
    }

}

