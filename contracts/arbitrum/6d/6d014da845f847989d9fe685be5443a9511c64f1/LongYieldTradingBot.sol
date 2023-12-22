// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import "./TradingBotBase.sol";
import "./BotActionHelper.sol";
import "./BotDecisionLib.sol";
import "./ILongYieldTradingBot.sol";
import "./UUPSUpgradeable.sol";

contract LongYieldTradingBot is
    TradingBotBase,
    BotActionHelper,
    ILongYieldTradingBot,
    UUPSUpgradeable
{
    LongTradingSpecs public specs;
    address public immutable decisionLib;

    constructor(
        address _market,
        address _PENDLE,
        address _decisionLib
    ) TradingBotBase(_market, _PENDLE) {
        decisionLib = _decisionLib;
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
        specs = _specs;
    }

    function swapSyToYt(
        address router,
        StrategyState memory oldState,
        ApproxParams calldata botParams,
        uint256 minYtOut,
        uint256 maxSyIn
    ) external onlyOwner returns (uint256 exactYtOut, uint256 netSyIn) {
        exactYtOut = BotDecisionLib(decisionLib).binarySearchUntilSwitchState(
            readBotState(),
            readMarketExtState(router),
            specs,
            ActionType.SwapSyToYt,
            oldState,
            botParams,
            botParams // only placeholder, value doesn't matter
        );

        if (exactYtOut < minYtOut) revert Errors.BotInsufficientYtOut(exactYtOut, minYtOut);
        netSyIn = _swapSyToYt(router, exactYtOut, maxSyIn);

        emit SwapSyToYt(oldState, botParams, maxSyIn, exactYtOut, netSyIn);
    }

    function addLiqKeepYt(
        address router,
        StrategyState memory oldState,
        ApproxParams calldata botParams,
        uint256 maxSyIn,
        uint256 minLpOut,
        uint256 minYtOut
    ) external onlyOwner returns (uint256 netSyIn, uint256 netLpOut, uint256 netYtOut) {
        netSyIn = BotDecisionLib(decisionLib).binarySearchUntilSwitchState(
            readBotState(),
            readMarketExtState(router),
            specs,
            ActionType.AddLiqKeepYt,
            oldState,
            botParams,
            botParams // only placeholder, value doesn't matter
        );

        if (netSyIn > maxSyIn) revert Errors.BotExceededLimitSyIn(netSyIn, maxSyIn);
        (netLpOut, netYtOut) = _addLiqKeepYt(router, netSyIn, minLpOut, minYtOut);

        emit AddLiqKeepYt(oldState, botParams, maxSyIn, netSyIn, netLpOut, netYtOut);
    }

    function addLiqFromSy(
        StrategyState memory oldState,
        ApproxParams calldata botParams,
        uint256 minLpOut,
        uint256 maxSyIn
    ) external onlyOwner returns (uint256 netPtFromSwap, uint256 netLpOut, uint256 netSyIn) {
        netPtFromSwap = BotDecisionLib(decisionLib).binarySearchUntilSwitchState(
            readBotState(),
            readMarketExtState(address(this)),
            specs,
            ActionType.AddLiqFromSy,
            oldState,
            botParams,
            botParams // only placeholder, value doesn't matter
        );

        (netLpOut, netSyIn) = _addLiqFromSy(netPtFromSwap, minLpOut, maxSyIn);

        emit AddLiqFromSy(oldState, botParams, maxSyIn, netSyIn, netLpOut);
    }

    function addLiqFromYt(
        StrategyState memory oldState,
        ApproxParams calldata botParams,
        uint256 minLpOut,
        uint256 maxYtIn
    ) external onlyOwner returns (uint256 netPtFromSwap, uint256 netLpOut, uint256 netYtIn) {
        netPtFromSwap = BotDecisionLib(decisionLib).binarySearchUntilSwitchState(
            readBotState(),
            readMarketExtState(address(this)),
            specs,
            ActionType.AddLiqFromYt,
            oldState,
            botParams,
            botParams // only placeholder, value doesn't matter
        );
        (netLpOut, netYtIn) = _addLiqFromYt(netPtFromSwap, minLpOut, maxYtIn);

        emit AddLiqFromYt(oldState, botParams, maxYtIn, netYtIn, netLpOut);
    }

    function removeLiqToYt(
        StrategyState memory oldState,
        ApproxParams calldata botParams,
        ApproxParams calldata guessTotalPtToSwap,
        uint256 maxLpRemoved,
        uint256 minYtOut
    ) external onlyOwner returns (uint256 netLpRemoved, uint256 netYtOut) {
        netLpRemoved = BotDecisionLib(decisionLib).binarySearchUntilSwitchState(
            readBotState(),
            readMarketExtState(address(this)),
            specs,
            ActionType.RemoveLiqToYt,
            oldState,
            botParams,
            guessTotalPtToSwap // value DOES matter
        );

        if (netLpRemoved > maxLpRemoved)
            revert Errors.BotExceededLimitLpToRemove(netLpRemoved, maxLpRemoved);

        netYtOut = _removeLiqToYt(netLpRemoved, guessTotalPtToSwap, minYtOut);

        emit RemoveLiqToYt(oldState, botParams, maxLpRemoved, netLpRemoved, netYtOut);
    }
}

