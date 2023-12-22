// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IERC20} from "./IERC20.sol";
import {IOracle} from "./IOracle.sol";
import {IStrategyHelper} from "./IStrategyHelper.sol";
import {IBalancerPool} from "./IBalancerPool.sol";
import {IBalancerVault} from "./IBalancerVault.sol";

contract OracleBalancerLPStable {
    IStrategyHelper public strategyHelper;
    IBalancerVault public vault;
    address public pool;

    constructor(address _strategyHelper, address _vault, address _pool) {
        strategyHelper = IStrategyHelper(_strategyHelper);
        vault = IBalancerVault(_vault);
        pool = _pool;
    }

    function decimals() external pure returns (uint8) {
        return 18;
    }

    function latestAnswer() external view returns (int256) {
        (address[] memory poolTokens,,) = vault.getPoolTokens(IBalancerPool(pool).getPoolId());
        uint256 length = poolTokens.length;
        uint256 minPrice = strategyHelper.price(poolTokens[0]);
        for (uint256 i = 1; i < length; i++) {
            if (poolTokens[i] == address(pool)) continue;
            uint256 tokenPrice = strategyHelper.price(poolTokens[i]);
            minPrice = (tokenPrice < minPrice) ? tokenPrice : minPrice;
        }
        return int256(minPrice * IBalancerPool(pool).getRate() / 1e18);
    }
}

