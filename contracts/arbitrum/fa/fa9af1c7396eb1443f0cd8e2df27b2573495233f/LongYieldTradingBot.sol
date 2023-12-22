// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import "./TradingBotBase.sol";
import "./BotActionHelper.sol";
import "./ILongYieldTradingBot.sol";
import "./UUPSUpgradeable.sol";

contract LongYieldTradingBot is
    TradingBotBase,
    BotActionHelper,
    ILongYieldTradingBot,
    UUPSUpgradeable
{
    LongTradingSpecs public specs;
    IBotDecisionHelper public immutable decisionHelper;

    constructor(
        address _market,
        address _PENDLE,
        address _decisionHelper
    ) TradingBotBase(_market, _PENDLE) {
        decisionHelper = BotDecisionHelper(_decisionHelper);
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    function initialize(LongTradingSpecs memory _specs) external initializer {
        _setSpecs(_specs);
        __BoringOwnable_init();
    }

    function setSpecs(LongTradingSpecs calldata _specs) external onlyOwner {
        _setSpecs(_specs);
    }

    function _setSpecs(LongTradingSpecs memory _specs) internal {
        require(_specs.lowerIyLimit <= _specs.upperIyLimit, "INVALID_IY_LIMITS");
        require(
            _specs.floatingSyRatioLimit >= _specs.floatingSyRatioTarget,
            "INVALID_FLOATING_SY_RATIO"
        );
        require(_specs.ytPtRatioLimit >= _specs.ytPtRatioTarget, "INVALID_YT_PT_RATIO");

        specs = _specs;
    }

    function swapSyToYt(
        address router,
        ApproxParams calldata botParams,
        uint256 minYtOut,
        uint256 maxSyIn
    ) external onlyOwner returns (uint256 exactYtOut, uint256 netSyIn) {
        (exactYtOut, ) = decisionHelper.searchForBotParam(
            readBotState(),
            readMarketExtState(router),
            specs,
            ActionType.SwapSyToYt,
            botParams,
            botParams // only placeholder, value doesn't matter
        );

        if (exactYtOut < minYtOut) revert Errors.BotInsufficientYtOut(exactYtOut, minYtOut);
        netSyIn = _swapSyToYt(router, exactYtOut, maxSyIn);

        emit SwapSyToYt(botParams, maxSyIn, exactYtOut, netSyIn);
    }

    function addLiqKeepYt(
        address router,
        ApproxParams calldata botParams,
        uint256 maxSyIn,
        uint256 minLpOut,
        uint256 minYtOut
    ) external onlyOwner returns (uint256 netSyIn, uint256 netLpOut, uint256 netYtOut) {
        (netSyIn, ) = decisionHelper.searchForBotParam(
            readBotState(),
            readMarketExtState(router),
            specs,
            ActionType.AddLiqKeepYt,
            botParams,
            botParams // only placeholder, value doesn't matter
        );

        if (netSyIn > maxSyIn) revert Errors.BotExceededLimitSyIn(netSyIn, maxSyIn);
        (netLpOut, netYtOut) = _addLiqKeepYt(router, netSyIn, minLpOut, minYtOut);

        emit AddLiqKeepYt(botParams, maxSyIn, netSyIn, netLpOut, netYtOut);
    }

    function addLiqFromSy(
        ApproxParams calldata botParams,
        uint256 minLpOut,
        uint256 maxSyIn
    ) external onlyOwner returns (uint256 netPtFromSwap, uint256 netLpOut, uint256 netSyIn) {
        (netPtFromSwap, ) = decisionHelper.searchForBotParam(
            readBotState(),
            readMarketExtState(address(this)),
            specs,
            ActionType.AddLiqFromSy,
            botParams,
            botParams // only placeholder, value doesn't matter
        );

        (netLpOut, netSyIn) = _addLiqFromSy(netPtFromSwap, minLpOut, maxSyIn);

        emit AddLiqFromSy(botParams, maxSyIn, netSyIn, netLpOut);
    }

    function addLiqFromYt(
        ApproxParams calldata botParams,
        uint256 minLpOut,
        uint256 maxYtIn
    ) external onlyOwner returns (uint256 netPtFromSwap, uint256 netLpOut, uint256 netYtIn) {
        (netPtFromSwap, ) = decisionHelper.searchForBotParam(
            readBotState(),
            readMarketExtState(address(this)),
            specs,
            ActionType.AddLiqFromYt,
            botParams,
            botParams // only placeholder, value doesn't matter
        );
        (netLpOut, netYtIn) = _addLiqFromYt(netPtFromSwap, minLpOut, maxYtIn);

        emit AddLiqFromYt(botParams, maxYtIn, netYtIn, netLpOut);
    }

    function removeLiqToYt(
        ApproxParams calldata botParams,
        ApproxParams calldata guessTotalPtToSwap,
        uint256 maxLpRemoved,
        uint256 minYtOut
    ) external onlyOwner returns (uint256 netLpRemoved, uint256 netYtOut, uint256 totalPtToSwap) {
        (netLpRemoved, ) = decisionHelper.searchForBotParam(
            readBotState(),
            readMarketExtState(address(this)),
            specs,
            ActionType.RemoveLiqToYt,
            botParams,
            guessTotalPtToSwap // value DOES matter
        );

        if (netLpRemoved > maxLpRemoved)
            revert Errors.BotExceededLimitLpToRemove(netLpRemoved, maxLpRemoved);

        (netYtOut, totalPtToSwap) = _removeLiqToYt(netLpRemoved, guessTotalPtToSwap, minYtOut);

        emit RemoveLiqToYt(botParams, maxLpRemoved, netLpRemoved, netYtOut);
    }
}

