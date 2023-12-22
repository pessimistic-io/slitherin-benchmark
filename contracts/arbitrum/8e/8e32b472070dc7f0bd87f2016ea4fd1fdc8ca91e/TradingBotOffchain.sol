// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import "./BotDecisionLib.sol";
import "./TokenAmountLib.sol";

contract TradingBotOffchain {
    using TokenAmountLib for TokenAmount[];
    using BotSimulationLib for BotState;
    using MarketMathCore for MarketState;
    using MarketApproxPtInLib for MarketState;
    using PYIndexLib for PYIndex;

    address immutable public decisionLib;

    constructor(address _decisionLib) {
        decisionLib = _decisionLib;
    }   

    /// SY interest from YT is excluded
    function claimForBot(
        address bot,
        address market
    ) external returns (TokenAmount[] memory rewards) {
        (IStandardizedYield SY, , IPYieldToken YT) = IPMarket(market).readTokens();

        address[] memory ytRewardTokens = YT.getRewardTokens();
        (, uint256[] memory ytRewardAmounts) = YT.redeemDueInterestAndRewards(bot, true, true);
        rewards = rewards.add(ytRewardTokens, ytRewardAmounts);

        address[] memory syRewardTokens = SY.getRewardTokens();
        uint256[] memory syRewardAmounts = SY.claimRewards(bot);
        rewards = rewards.add(syRewardTokens, syRewardAmounts);

        address[] memory lpRewardTokens = IPMarket(market).getRewardTokens();
        uint256[] memory lpRewardAmounts = IPMarket(market).redeemRewards(bot);
        rewards = rewards.add(lpRewardTokens, lpRewardAmounts);
    }

    function simulateAction(
        BotState calldata botCalldata,
        MarketExtState calldata marketExtCalldata,
        ActionType action,
        uint256 botParam,
        ApproxParams memory swapApproxParams
    ) external view returns (bool success, BotState memory bot, MarketExtState memory marketExt) {
        bot = botCalldata;
        marketExt = marketExtCalldata;

        if (action == ActionType.SwapSyToYt) {
            success = bot.swapSyToYt(marketExt, botParam);
        } else if (action == ActionType.AddLiqKeepYt) {
            success = bot.addLiqKeepYt(marketExt, botParam);
        } else if (action == ActionType.AddLiqFromSy) {
            success = bot.addLiqFromSy(marketExt, botParam);
        } else if (action == ActionType.AddLiqFromYt) {
            success = bot.addLiqFromYt(marketExt, botParam);
        } else if (action == ActionType.RemoveLiqToYt) {
            success = bot.removeLiqToYt(marketExt, botParam, swapApproxParams);
        } else {
            success = false;
        }
    }

    function searchForBotParam(
        BotState calldata bot,
        MarketExtState calldata marketExt,
        LongTradingSpecs calldata specs,
        ActionType action,
        StrategyState calldata initialState,
        ApproxParams calldata botParams,
        ApproxParams calldata intParams
    ) external view returns (uint256) {
        return
            BotDecisionLib(decisionLib).binarySearchUntilSwitchState(
                bot,
                marketExt,
                specs,
                action,
                initialState,
                botParams,
                intParams
            );
    }

    function searchForIntParam(
        MarketExtState calldata marketExt,
        ActionType action,
        uint256 botParam,
        ApproxParams calldata intParams
    ) external view returns (uint256) {
        if (action == ActionType.RemoveLiqToYt) {
            return _searchForIntParamRemoveLiqToYt(marketExt, botParam, intParams);
        } else {
            return 0;
        }
    }

    function strategyState(
        BotState calldata bot,
        MarketExtState calldata marketExt,
        LongTradingSpecs calldata specs
    ) external view returns (StrategyState memory) {
        return BotDecisionLib(decisionLib).strategyState(bot, marketExt, specs);
    }

    function actionToTake(StrategyState memory currentState) external view returns (ActionType) {
        return BotDecisionLib(decisionLib).actionToTake(currentState);
    }

    function tvlInSy(
        BotState calldata bot,
        MarketExtState calldata marketExt
    ) external view returns (uint256) {
        return BotSimulationLib.tvlInSy(bot, marketExt);
    }

    function _searchForIntParamRemoveLiqToYt(
        MarketExtState memory marketExt,
        uint256 netLpToRemove,
        ApproxParams memory intParams
    ) private view returns (uint256 totalPtToSwap) {
        (uint256 netSyRemoved, uint256 netPtRemoved) = marketExt.state.removeLiquidity(
            netLpToRemove
        );

        uint256 netYtFromSy = marketExt.index.syToAsset(netSyRemoved);
        uint256 netPtToSwap = netPtRemoved + netYtFromSy;

        (, totalPtToSwap, ) = marketExt.state.approxSwapExactPtForYt(
            marketExt.index,
            netPtToSwap,
            marketExt.blockTime,
            intParams
        );
    }
}

