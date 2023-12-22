// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "./AccessControlEnumerable.sol";
import "./IPriceOracleManager.sol";
import "./IPriceConsumer.sol";

contract PriceOracleManagerV1 is IPriceOracleManager, AccessControlEnumerable {
    address[] public oracles;

    uint256 public validPriceDuration = 1 minutes;

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function addOracle(address oracle) external onlyRole(DEFAULT_ADMIN_ROLE) {
        oracles.push(oracle);
    }

    function getPriceInUSD(address token) external override returns (uint256) {
        for (uint256 i = 0; i < oracles.length; i++) {
            IPriceConsumer oracle = IPriceConsumer(oracles[i]);
            uint256 minTimestamp = block.timestamp - validPriceDuration;
            try oracle.fetchPriceInUSD(token, minTimestamp) {
                (uint256 price, uint256 timestamp) = oracle.getPriceInUSD(token);
                if (block.timestamp - timestamp > validPriceDuration) {
                    // too old, look at the next oracle
                    continue;
                }
                return price;
            } catch {
                // oracle failed, look at the next oracle
                continue;
            }
        }
        return 0;
    }

    function getOracles() external view returns (address[] memory) {
        return oracles;
    }

    function removeOracle(uint256 index) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (index != oracles.length - 1) {
            oracles[index] = oracles[oracles.length - 1];
        }
        oracles.pop();
    }

    function setValidPriceDuration(uint256 duration) external onlyRole(DEFAULT_ADMIN_ROLE) {
        validPriceDuration = duration;
    }
}

