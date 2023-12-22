// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IERC20} from "./IERC20.sol";
import {IOracle} from "./IOracle.sol";
import {IPairUniV2} from "./IPairUniV2.sol";

contract OracleUniswapV2Eth {
    IPairUniV2 public pair;
    address public weth;
    IOracle public ethOracle;
    address public token0;
    address public token1;
    uint8 public decimals0;
    uint8 public decimals1;

    constructor(address _pair, address _weth, address _ethOracle) {
        pair = IPairUniV2(_pair);
        weth = _weth;
        ethOracle = IOracle(_ethOracle);
        token0 = pair.token0();
        token1 = pair.token1();
        decimals0 = IERC20(token0).decimals();
        decimals1 = IERC20(token1).decimals();
    }

    function decimals() external pure returns (uint8) {
        return 18;
    }

    function latestAnswer() external view returns (int256) {
        (uint256 reserve0, uint256 reserve1,) = pair.getReserves();
        reserve0 = reserve0 * 1e18 / (10 ** decimals0);
        reserve1 = reserve1 * 1e18 / (10 ** decimals1);
        uint256 price = token0 == weth ? reserve0 * 1e18 / reserve1 : reserve1 * 1e18 / reserve0;
        return int256(price) * ethOracle.latestAnswer() / int256(10 ** ethOracle.decimals());
    }
}

