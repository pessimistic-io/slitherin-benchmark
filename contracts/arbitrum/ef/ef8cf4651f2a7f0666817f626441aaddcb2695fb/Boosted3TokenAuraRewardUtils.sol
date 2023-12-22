// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {     ThreeTokenPoolContext,      ReinvestRewardParams,      SingleSidedRewardTradeParams,     StrategyContext } from "./VaultTypes.sol";
import {VaultEvents} from "./VaultEvents.sol";
import {Errors} from "./Errors.sol";
import {BalancerConstants} from "./BalancerConstants.sol";
import {Balancer3TokenBoostedPoolUtils} from "./Balancer3TokenBoostedPoolUtils.sol";
import {StrategyUtils} from "./StrategyUtils.sol";
import {RewardUtils} from "./RewardUtils.sol";
import {ILinearPool} from "./IBalancerPool.sol";
import {IERC20} from "./interfaces_IERC20.sol";

library Boosted3TokenAuraRewardUtils {
    using StrategyUtils for StrategyContext;

    function _validateTrade(
        IERC20[] memory rewardTokens,
        SingleSidedRewardTradeParams memory params,
        address primaryToken
    ) private view {
        // Validate trades
        if (!RewardUtils._isValidRewardToken(rewardTokens, params.sellToken)) {
            revert Errors.InvalidRewardToken(params.sellToken);
        }
        if (params.buyToken != ILinearPool(primaryToken).getMainToken()) {
            revert Errors.InvalidRewardToken(params.buyToken);
        }
    }

    function _executeRewardTrades(
        ThreeTokenPoolContext calldata poolContext,
        StrategyContext memory strategyContext,
        IERC20[] memory rewardTokens,
        bytes calldata data
    ) internal returns (address rewardToken, uint256 primaryAmount) {
        SingleSidedRewardTradeParams memory params = abi.decode(data, (SingleSidedRewardTradeParams));

        _validateTrade(rewardTokens, params, poolContext.basePool.primaryToken);

        (/*uint256 amountSold*/, primaryAmount) = strategyContext._executeTradeExactIn({
            params: params.tradeParams,
            sellToken: params.sellToken,
            buyToken: params.buyToken,
            amount: params.amount,
            useDynamicSlippage: false
        });

        rewardToken = params.sellToken;
    }
}

