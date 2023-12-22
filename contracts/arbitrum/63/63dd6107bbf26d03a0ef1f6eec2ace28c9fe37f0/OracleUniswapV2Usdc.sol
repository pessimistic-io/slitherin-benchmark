// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IERC20} from "./IERC20.sol";
import {IOracle} from "./IOracle.sol";
import {IPairUniV2} from "./IPairUniV2.sol";

// WARNING: This oracle is not manipulation resistant, use with OracleTWAP in front
contract OracleUniswapV2Usdc {
    IPairUniV2 public pair;
    address public usdc;
    address public token0;
    address public token1;

    constructor(address _pair, address _usdc) {
        pair = IPairUniV2(_pair);
        usdc = _usdc;
        token0 = pair.token0();
        token1 = pair.token1();
    }

    function decimals() external pure returns (uint8) {
        return 18;
    }

    function latestAnswer() external view returns (int256) {
        (uint256 reserve0, uint256 reserve1,) = pair.getReserves();
        if (token0 == usdc) {
            return int256((reserve0 * 1e18 / 1e6) * 1e18 / reserve1);
        } else {
            return int256((reserve1 * 1e18 / 1e6) * 1e18 / reserve0);
        }
    }
}

