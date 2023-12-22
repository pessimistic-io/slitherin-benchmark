// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IERC20} from "./IERC20.sol";
import {IOracle} from "./IOracle.sol";
import {IPairUniV2} from "./IPairUniV2.sol";

contract OracleUniswapV2 {
    IPairUniV2 public pair;
    address public weth;
    IOracle public ethOracle;
    address public token0;
    address public token1;
    uint256[4] public prices;
    uint256 public lastIndex;
    uint256 public lastTimestamp;
    uint256 public constant updateInterval = 30 minutes;

    constructor(address _pair, address _weth, address _ethOracle) {
        pair = IPairUniV2(_pair);
        weth = _weth;
        ethOracle = IOracle(_ethOracle);
        token0 = pair.token0();
        token1 = pair.token1();
        uint256 price = currentPrice();
        prices = [price, price, price, price];
        lastTimestamp = block.timestamp;
    }

    function decimals() external pure returns (uint8) {
        return 18;
    }

    function latestAnswer() external view returns (int256) {
      require(block.timestamp < lastTimestamp + (updateInterval * 2), "stale price");
      uint256 price = (prices[0] + prices[1] + prices[2] + prices[3]) / 4;
      return int256(price) *
        ethOracle.latestAnswer() /
        int256(10 ** ethOracle.decimals());
    }

    function update() external {
        require(block.timestamp > lastTimestamp + updateInterval, "before next update");
        lastIndex = (lastIndex + 1) % 4;
        prices[lastIndex] = currentPrice();
        lastTimestamp = block.timestamp;
    }

    function currentPrice() public view returns (uint256) {
        (uint256 reserve0, uint256 reserve1,) = pair.getReserves();
        if (token0 == weth) {
            return reserve0 * 1e18 / reserve1;
        } else {
            return reserve1 * 1e18 / reserve0;
        }
    }
}

