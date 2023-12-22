// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {OwnableUpgradeable} from "./OwnableUpgradeable.sol";
import {jTokensOracle} from "./jTokensOracle.sol";

contract OracleAggregator is OwnableUpgradeable {
    mapping(address => jTokensOracle) public oracles;

    function initialize() external initializer {
        __Ownable_init();
    }

    function getUsdPrice(address _asset) external view returns (uint256) {
        jTokensOracle oracle = oracles[_asset];

        return uint256(oracle.getLatestPrice());
    }

    function addOracle(address _oracle) external onlyOwner {
        if (_oracle == address(0)) {
            revert Invalid();
        }

        jTokensOracle oracle = jTokensOracle(_oracle);
        oracles[oracle.asset()] = oracle;

        emit NewOracle(_oracle, oracle.asset());
    }

    function getOracle(address _asset) external view returns (jTokensOracle) {
        return oracles[_asset];
    }

    error Invalid();

    event NewOracle(address indexed _oracle, address indexed _asset);
}

