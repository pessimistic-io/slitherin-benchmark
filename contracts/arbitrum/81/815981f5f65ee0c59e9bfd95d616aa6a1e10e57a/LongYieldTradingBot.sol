// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import "./TradingBotBase.sol";
import "./LongYieldActionLib.sol";
import "./ILongYieldTradingBot.sol";
import "./IPMarketSwapCallback.sol";
import "./UUPSUpgradeable.sol";

// High level audit notes:
// -    This bot is a ERC5115 upgradable token where users can deposit SY to mint/burn share to get back SY
// -    All functions related to the bot's funds (making changes in the bot's balance/doing approvals) should
//      be executable by only owner

contract LongYieldTradingBot is
    TradingBotBase,
    UUPSUpgradeable,
    ILongYieldTradingBot,
    IPMarketSwapCallback
{
    using MarketExtLib for MarketExtState;
    using Math for uint256;
    using Math for int256;

    constructor(
        address _market,
        address _router,
        address _PENDLE,
        address _decisionHelper
    ) TradingBotBase(_market, _router, _PENDLE, _decisionHelper) {}

    function _authorizeUpgrade(address) internal override onlyOwner {}

    function initialize(TradingSpecs memory _specs) external initializer {
        _setSpecs(_specs);
        __BoringOwnable_init();
    }

    function liquidateLpToSy(
        uint256 netLpToRemove,
        uint256 minSyOut
    ) external returns (uint256 netSyOut) {
        return LongYieldActionLib.liquidateLpToSy(market, netLpToRemove, minSyOut);
    }

    // More docs in LongYieldActionLib.sol
    function removeLiquidityToSy(
        uint256 netLpToRemove,
        uint256 minSyOut
    ) external onlyOwner returns (uint256 netSyOut) {
        return LongYieldActionLib.removeLiquidityToSy(market, netLpToRemove, minSyOut);
    }

    // More docs in LongYieldActionLib.sol
    function swapYtToSy(
        uint256 netYtToSell,
        uint256 minSyOut
    ) external onlyOwner returns (uint256 netSyOut) {
        return LongYieldActionLib.swapYtToSy(market, netYtToSell, minSyOut);
    }

    // @inheritdocs ILongYieldTradingBot
    function addLiqKeepYt(
        uint256 netSyIn,
        uint256 minLpOut,
        uint256 minYtOut
    ) external onlyOwner returns (uint256 netLpOut, uint256 netYtOut) {
        (netLpOut, netYtOut) = LongYieldActionLib.addLiqKeepYt(
            market,
            netSyIn,
            minLpOut,
            minYtOut
        );
        emit AddLiqKeepYt(netSyIn, netLpOut, netYtOut);
    }

    // @inheritdocs ILongYieldTradingBot
    function addLiqFromYt(
        AddLiqFromYtInput calldata inputParams
    ) external onlyOwner returns (uint256 netPtFromSwap, uint256 netLpOut, uint256 netYtIn) {
        StrategyData memory strategyData = readStrategyData();

        require(
            IBotDecisionHelper(decisionHelper).getCurrentBin(strategyData) ==
                inputParams.currentBin,
            "addLiqFromYt: bin state expired"
        );
        netPtFromSwap = decisionHelper.searchForBotParam(
            readStrategyData(),
            TradeActionType.AddLiqFromYt,
            inputParams.targetIy,
            type(uint256).max,
            inputParams.botParams,
            inputParams.botParams // only placeholder, value doesn't matter
        );
        (netLpOut, netYtIn) = LongYieldActionLib.addLiqFromYt(
            market,
            netPtFromSwap,
            inputParams.minLpOut
        );

        _updateSellBinAfterTrade();

        emit AddLiqFromYt(inputParams.botParams, netYtIn, netLpOut);
    }

    // @inheritdocs ILongYieldTradingBot
    function removeLiqToYt(
        RemoveLiqToYtInput calldata inputParams
    ) external onlyOwner returns (uint256 netLpRemoved, uint256 netYtOut) {
        StrategyData memory strategyData = readStrategyData();

        require(
            IBotDecisionHelper(decisionHelper).getCurrentBin(strategyData) ==
                inputParams.currentBin,
            "removeLiqToYt: bin state expired"
        );

        netLpRemoved = decisionHelper.searchForBotParam(
            strategyData,
            TradeActionType.RemoveLiqToYt,
            inputParams.targetIy,
            type(uint256).max,
            inputParams.botParams,
            inputParams.guessTotalPtToSwap // value DOES matter
        );

        (netYtOut, ) = LongYieldActionLib.removeLiqToYt(
            market,
            netLpRemoved,
            inputParams.guessTotalPtToSwap,
            inputParams.minYtOut
        );

        _updateSellBinAfterTrade();

        emit RemoveLiqToYt(inputParams.botParams, netLpRemoved, netYtOut);
    }

    function swapCallback(int256 ptToAccount, int256 syToAccount, bytes calldata data) external {
        require(msg.sender == market, "unauthorized call back");
        LongYieldActionLib.swapCallback(market, ptToAccount, syToAccount, data);
    }
}

