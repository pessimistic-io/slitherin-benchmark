// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IERC20} from "./IERC20.sol";
import {IPairUniV2} from "./IPairUniV2.sol";
import {IStrategyHelper} from "./IStrategyHelper.sol";

contract OracleUniswapV2Pair {
    IStrategyHelper public strategyHelper;
    IPairUniV2 public pair;
    address public token0;
    address public token1;

    constructor(address _strategyHelper, address _pair) {
        strategyHelper = IStrategyHelper(_strategyHelper);
        pair = IPairUniV2(_pair);
        token0 = pair.token0();
        token1 = pair.token1();
    }

    function decimals() external pure returns (uint8) {
        return 18;
    }

    function latestAnswer() external view returns (int256) {
        IPairUniV2 p = pair;
        IERC20 tok0 = IERC20(p.token0());
        IERC20 tok1 = IERC20(p.token1());
        uint256 tot = p.totalSupply();
        (uint112 r0, uint112 r1,) = p.getReserves();
        uint256 reserve0 = uint256(r0) * 1e18 / (10 ** tok0.decimals());
        uint256 reserve1 = uint256(r1) * 1e18 / (10 ** tok1.decimals());
        uint256 price0 = strategyHelper.price(address(tok0));
        uint256 price1 = strategyHelper.price(address(tok1));
        return 2 * int256((sqrt(reserve0 * reserve1) * sqrt(price0 * price1)) / tot);
    }

    // from OZ Math
    function sqrt(uint256 a) internal pure returns (uint256) {
        if (a == 0) return 0;
        uint256 result = 1 << (log2(a) >> 1);
        unchecked {
            result = (result + a / result) >> 1;
            result = (result + a / result) >> 1;
            result = (result + a / result) >> 1;
            result = (result + a / result) >> 1;
            result = (result + a / result) >> 1;
            result = (result + a / result) >> 1;
            result = (result + a / result) >> 1;
            return min(result, a / result);
        }
    }

    function log2(uint256 value) internal pure returns (uint256) {
        uint256 result = 0;
        unchecked {
            if (value >> 128 > 0) {
                value >>= 128;
                result += 128;
            }
            if (value >> 64 > 0) {
                value >>= 64;
                result += 64;
            }
            if (value >> 32 > 0) {
                value >>= 32;
                result += 32;
            }
            if (value >> 16 > 0) {
                value >>= 16;
                result += 16;
            }
            if (value >> 8 > 0) {
                value >>= 8;
                result += 8;
            }
            if (value >> 4 > 0) {
                value >>= 4;
                result += 4;
            }
            if (value >> 2 > 0) {
                value >>= 2;
                result += 2;
            }
            if (value >> 1 > 0) result += 1;
        }
        return result;
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}

