// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IERC20} from "./IERC20.sol";
import {IOracle} from "./IOracle.sol";
import {IStrategyHelper} from "./IStrategyHelper.sol";
import {IBalancerPool} from "./IBalancerPool.sol";
import {IBalancerVault} from "./IBalancerVault.sol";

contract OracleBalancer5050ETH {
    IBalancerVault public vault;
    IBalancerPool public pool;
    IOracle public ethOracle;
    uint256 public tokenIndex;
    uint256 public wethIndex;

    constructor(address _vault, address _pool, address _ethOracle, address _weth) {
        vault = IBalancerVault(_vault);
        pool = IBalancerPool(_pool);
        ethOracle = IOracle(_ethOracle);
        (address[] memory poolTokens,,) = vault.getPoolTokens(IBalancerPool(pool).getPoolId());
        uint256[] memory weights = pool.getNormalizedWeights();
        require(poolTokens.length == 2, "pool has more than 2 tokens");
        require(weights[0] == 0.5e18 && weights[1] == 0.5e18, "pool weights not 50/50");
        if (poolTokens[0] == _weth) {
          tokenIndex = 1;
          wethIndex = 0;
        } else {
          tokenIndex = 0;
          wethIndex = 1;
        }
    }

    function decimals() external pure returns (uint8) {
        return 18;
    }

    function latestAnswer() external view returns (int256) {
        int256 ethPrice = ethOracle.latestAnswer() * 1e18 / int256(10 ** ethOracle.decimals());
        (, uint256[] memory balances,) = vault.getPoolTokens(IBalancerPool(pool).getPoolId());
        int256 tokenPrice = int256(balances[tokenIndex] * 1e18 / balances[wethIndex]);
        return int256(ethPrice * 1e18 / tokenPrice);
    }
}

