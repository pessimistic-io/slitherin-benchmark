// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IERC20} from "./IERC20.sol";
import {IOracle} from "./IOracle.sol";
import {IUniswapV3Pool} from "./IUniswapV3Pool.sol";
import {OracleLibrary} from "./OracleLibrary.sol";

contract OracleUniswapV3 {
    address public pool;
    address public weth;
    IOracle public ethOracle;
    uint32 public constant twapPeriod = 1800;

    constructor(address _pool, address _weth, address _ethOracle) {
        pool = _pool;
        weth = _weth;
        ethOracle = IOracle(_ethOracle);
    }

    function decimals() external pure returns (uint8) {
        return 18;
    }

    function latestAnswer() external view returns (int256) {
      address tok = IUniswapV3Pool(pool).token0();
      if (tok == weth) {
        tok = IUniswapV3Pool(pool).token1();
      }
      (int24 amt,) = OracleLibrary.consult(pool, twapPeriod);
      uint256 pri = OracleLibrary.getQuoteAtTick(
          amt,
          uint128(10) ** IERC20(tok).decimals(),
          tok,
          weth
      );
      return int256(pri) *
        ethOracle.latestAnswer() /
        int256(10 ** ethOracle.decimals());
    }
}

