// SPDX-License-Identifier: MIT
pragma solidity >=0.4.0 <0.8.0;

import "./IUniswapV3Pool.sol";
import "./IUniswapV3Factory.sol";
import "./TickMath.sol";
import "./FixedPoint96.sol";
import "./FullMath.sol";
import "./IERC20.sol";

contract Univ3Twap {

    address UNI_FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984;

    function getPoolAddress(address token0, address token1, uint24 fee) public view returns (address) {
        return IUniswapV3Factory(UNI_FACTORY).getPool(token0, token1, fee);
    }

    function getSqrtTwapX96(address uniswapV3Pool, uint32 twapInterval) public view returns (uint160 sqrtPriceX96) {
        if (twapInterval == 0) {
            // return the current price if twapInterval == 0
            (sqrtPriceX96, , , , , , ) = IUniswapV3Pool(uniswapV3Pool).slot0();
        } else {
            uint32[] memory secondsAgos = new uint32[](2);
            secondsAgos[0] = twapInterval; // from (before)
            secondsAgos[1] = 0; // to (now)

            (int56[] memory tickCumulatives, ) = IUniswapV3Pool(uniswapV3Pool).observe(secondsAgos);

            // tick(imprecise as it's an integer) to price
            sqrtPriceX96 = TickMath.getSqrtRatioAtTick(
                int24((tickCumulatives[1] - tickCumulatives[0]) / twapInterval)
            );
        }
    }

    function getPriceX96FromSqrtPriceX96(uint160 sqrtPriceX96) public pure returns(uint256 priceX96) {
        return FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, FixedPoint96.Q96);
    }

    function sqrtPriceX96ToUint(uint160 sqrtPriceX96, uint8 decimalsToken0)
        public
        pure
        returns (uint256)
    {
        uint256 numerator1 = uint256(sqrtPriceX96) * uint256(sqrtPriceX96);
        uint256 numerator2 = 10**decimalsToken0;
        return FullMath.mulDiv(numerator1, numerator2, 1 << 192);
    }

    function getSingleHopTwap(address token0, address token1, uint24 fee, uint32 twapLength) public view returns(uint256) {
        address poolAddress = getPoolAddress(token0, token1, fee);
        uint160 sqrtPriceX96 = getSqrtTwapX96(poolAddress, twapLength);
        address poolToken0 = IUniswapV3Pool(poolAddress).token0();
        uint256 twap = sqrtPriceX96ToUint(sqrtPriceX96, IERC20(poolToken0).decimals());
        if(poolToken0 != token0) {
            twap = 10**IERC20(token0).decimals() * 10**IERC20(token1).decimals() / twap;
        }
        return twap;
    }

    function getTwap(address[] calldata path, uint24[] calldata fees, uint32 twapLength) public view returns(uint256) {
        require(fees.length == path.length-1, "invalid params");

        if(path.length == 2) {
            return getSingleHopTwap(path[0], path[1], fees[0], twapLength);
        }

        uint256 twap = 1;
        uint256 decimals = 0;

        for(uint i = 0; i < path.length-1; i++) {
            uint256 t = getSingleHopTwap(path[i], path[i+1], fees[i], twapLength);
            twap = twap * t; 
            decimals += IERC20(path[i+1]).decimals();
        }

        return twap * 10**IERC20(path[path.length-1]).decimals() / 10**decimals;
    }
}
