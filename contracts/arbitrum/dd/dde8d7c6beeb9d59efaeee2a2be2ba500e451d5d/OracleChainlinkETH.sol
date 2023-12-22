// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IERC20} from "./IERC20.sol";
import {IOracle} from "./IOracle.sol";

contract OracleChainlinkETH {
    IOracle public oracle;
    IOracle public ethOracle;

    constructor(address _oracle, address _ethOracle) {
        oracle = IOracle(_oracle);
        ethOracle = IOracle(_ethOracle);
    }

    function decimals() external pure returns (uint8) {
        return 18;
    }

    function latestAnswer() external view returns (int256) {
      int256 price = oracle.latestAnswer() * 1e18 / int256(10 ** oracle.decimals());
      return price * ethOracle.latestAnswer() / int256(10 ** ethOracle.decimals());
    }
}

