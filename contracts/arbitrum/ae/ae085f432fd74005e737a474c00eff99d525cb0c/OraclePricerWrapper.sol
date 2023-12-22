// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import { IERC20 } from "./IERC20.sol";
import { ITimeWeightedAveragePricer } from "./ITimeWeightedAveragePricer.sol";
import { IOracle } from "./IStakeValuator.sol";
import { Ownable } from "./Ownable.sol";

contract OraclePriceWrapper is IOracle, Ownable {
    ITimeWeightedAveragePricer public oracle;

    event OracleSet(ITimeWeightedAveragePricer indexed oldOracle, ITimeWeightedAveragePricer indexed newOracle);

    constructor(ITimeWeightedAveragePricer _oracle) {
        setOracle(_oracle);
    }

    function setOracle(ITimeWeightedAveragePricer _oracle) public onlyOwner {
        emit OracleSet(oracle, _oracle);
        oracle = _oracle;
    }

    function getPrice(IERC20 token) external view override returns (uint256, uint256) {
        if (address(token) == address(oracle.token0())) {
            return (oracle.getToken0Price(), oracle.getOldestSampleBlock());
        } else if (address(token) == address(oracle.token1())) {
            return (oracle.getToken0Price(), oracle.getOldestSampleBlock());
        } else {
            require(false, 'OraclePriceWrapper: invalid token');
        }
    }
}

