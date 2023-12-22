// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {FullMath} from "./FullMath.sol";
import {IERC20} from "./IERC20.sol";
import {IOracle} from "./IOracle.sol";
import {IJoeLBPair} from "./IJoe.sol";

contract OracleTraderJoe {
    IJoeLBPair public pair;
    address public weth;
    IOracle public ethOracle;
    uint256 public constant twapPeriod = 1800;

    constructor(address _pair, address _weth, address _ethOracle) {
        pair = IJoeLBPair(_pair);
        weth = _weth;
        ethOracle = IOracle(_ethOracle);
    }

    function decimals() external pure returns (uint8) {
        return 18;
    }

    function latestAnswer() external view returns (int256) {
        address tok = pair.getTokenX();
        if (tok == weth) {
            tok = pair.getTokenY();
        }
        (uint256 cumId1,,) = pair.getOracleSampleAt(uint40(block.timestamp));
        (uint256 cumId0,,) = pair.getOracleSampleAt(uint40(block.timestamp-twapPeriod));
        uint24 avgId = uint24(uint256(cumId1-cumId0) / twapPeriod);
        uint256 price = FullMath.mulDiv(pair.getPriceFromId(avgId), 1e18, 1 << 128);
        if (pair.getTokenX() == weth) {
            price = 1e18 * 1e18 / price;
        }
        price = price * (10 ** IERC20(tok).decimals()) / 1e18;
        return int256(price) * ethOracle.latestAnswer() / int256(10 ** ethOracle.decimals());
    }
}

