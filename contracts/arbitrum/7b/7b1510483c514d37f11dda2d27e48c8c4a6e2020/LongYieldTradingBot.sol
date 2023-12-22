// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import "./TradingBotBase.sol";
import "./LongYieldActionHelper.sol";
import "./ILongYieldTradingBot.sol";
import "./UUPSUpgradeable.sol";

contract LongYieldTradingBot is
    TradingBotBase,
    LongYieldActionHelper,
    ILongYieldTradingBot,
    UUPSUpgradeable
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

    function addLiqKeepYt(
        uint256 netSyIn,
        uint256 minLpOut,
        uint256 minYtOut
    ) external onlyOwner returns (uint256 netLpOut, uint256 netYtOut) {
        (netLpOut, netYtOut) = _addLiqKeepYt(router, netSyIn, minLpOut, minYtOut);
        emit AddLiqKeepYt(netSyIn, netLpOut, netYtOut);
    }

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
            ActionType.AddLiqFromYt,
            inputParams.targetIy,
            type(uint256).max,
            inputParams.botParams,
            inputParams.botParams // only placeholder, value doesn't matter
        );
        (netLpOut, netYtIn) = _addLiqFromYt(netPtFromSwap, inputParams.minLpOut);

        _updateSellBinAfterTrade();

        emit AddLiqFromYt(inputParams.botParams, netYtIn, netLpOut);
    }

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
            ActionType.RemoveLiqToYt,
            inputParams.targetIy,
            type(uint256).max,
            inputParams.botParams,
            inputParams.guessTotalPtToSwap // value DOES matter
        );

        (netYtOut, ) = _removeLiqToYt(
            netLpRemoved,
            inputParams.guessTotalPtToSwap,
            inputParams.minYtOut
        );

        _updateSellBinAfterTrade();

        emit RemoveLiqToYt(inputParams.botParams, netLpRemoved, netYtOut);
    }
}

