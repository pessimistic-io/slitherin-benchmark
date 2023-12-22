// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import "./TradingBotBase.sol";
import "./ShortYieldActionHelper.sol";
import "./IShortYieldTradingBot.sol";
import "./UUPSUpgradeable.sol";

contract ShortYieldTradingBot is
    TradingBotBase,
    ShortYieldActionHelper,
    IShortYieldTradingBot,
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

    function mintPY(
        uint256 netSyIn,
        uint256 minPyOut
    ) external onlyOwner returns (uint256 netPyOut) {
        netPyOut = _mintPY(netSyIn, minPyOut);
        emit MintPy(netSyIn, minPyOut);
    }

    function swapPtForYt(
        SwapInput calldata inputParams
    ) external onlyOwner returns (uint256 netYtOut) {
        StrategyData memory strategyData = readStrategyData();

        require(
            IBotDecisionHelper(decisionHelper).getCurrentBin(strategyData) ==
                inputParams.currentBin,
            "removeLiqToYt: bin state expired"
        );

        uint256 netPtToSwap = decisionHelper.searchForBotParam(
            strategyData,
            ActionType.SwapPtForYt,
            inputParams.targetIy,
            type(uint256).max,
            inputParams.botParams,
            inputParams.guessTotalPtToSwap
        );

        netYtOut = _swapPtForYt(
            netPtToSwap,
            inputParams.guessTotalPtToSwap,
            inputParams.minAmountOut
        );

        _updateSellBinAfterTrade();

        emit SwapPtForYt(inputParams, netYtOut);
    }

    function swapYtForPt(
        SwapInput calldata inputParams
    ) external onlyOwner returns (uint256 netPtOut) {
        StrategyData memory strategyData = readStrategyData();

        require(
            IBotDecisionHelper(decisionHelper).getCurrentBin(strategyData) ==
                inputParams.currentBin,
            "removeLiqToYt: bin state expired"
        );

        uint256 netYtToSwap = decisionHelper.searchForBotParam(
            strategyData,
            ActionType.SwapYtForPt,
            inputParams.targetIy,
            type(uint256).max,
            inputParams.botParams,
            inputParams.guessTotalPtToSwap
        );

        netPtOut = _swapYtForPt(
            netYtToSwap,
            inputParams.guessTotalPtToSwap,
            inputParams.minAmountOut
        );

        _updateSellBinAfterTrade();
        emit SwapYtForPt(inputParams, netPtOut);
    }
}

