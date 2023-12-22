// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import "./IPAllAction.sol";
import "./TokenAmountLib.sol";
import "./MarketExtLib.sol";

struct BotState {
    uint256 lpBalance;
    uint256 ytBalance;
    uint256 ptBalance;
    uint256 syBalance;
    uint256 buyBins;
}

struct TradingSpecs {
    uint256 buyYtIy;
    uint256 sellYtIy;
    uint256 targetSyRatio;
    uint256 maxSyRatio;
    uint256 targetYtPtRatio;
    uint256 numOfBins;
}

struct StrategyData {
    BotState botState;
    MarketExtState marketExt;
    TradingSpecs specs;
}

interface ITradingBotBase {
    struct MultiApproval {
        address[] tokens;
        address spender;
    }

    event DepositSy(uint256 netSyIn);

    event DepositToken(address indexed token, uint256 netTokenIn);

    event WithdrawFunds(address indexed token, uint256 amount);

    event ClaimAndCompound(uint256 netSyOut, uint256 netPendleOut);

    function approveInf(MultiApproval[] calldata arr) external;

    function depositSy(uint256 netSyIn) external;

    function depositToken(TokenInput calldata inp, uint256 minSyOut) external payable;

    function withdrawFunds(address token, uint256 amount) external;

    function claimAndCompound(
        TokenInput[] calldata inps,
        uint256 minSyOut
    ) external returns (uint256 netSyOut, uint256 netPendleOut);

    function claimWithoutCompound() external returns (TokenAmount[] memory rewards);

    function readStrategyData() external returns (StrategyData memory strategyData);

    function setSpecs(TradingSpecs calldata _specs) external;
}

