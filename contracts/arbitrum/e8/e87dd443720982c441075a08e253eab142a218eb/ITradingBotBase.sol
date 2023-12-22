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
    uint256 buyBins; // Number of buyable bins (buy bins + sell bins = 2 * numOfBins)
}

// For specs explanation, see the Fortknox design docs
struct TradingSpecs {
    uint256 buyYtIy;
    uint256 sellYtIy;
    uint256 targetSyRatio;
    uint256 bufferSyRatio;
    uint256 minYtPtRatio;
    uint256 numOfBins;
}

struct StrategyData {
    BotState botState;
    MarketExtState marketExt;
    TradingSpecs specs;
}

interface ITradingBotBase {
    event DepositSy(uint256 netSyIn);

    event DepositToken(address indexed token, uint256 netTokenIn);

    event WithdrawFunds(address indexed token, uint256 amount);

    event ClaimAndCompound(uint256 netSyOut);

    /**
     * To compound the reward tokens in to SY by swapping through router (IPActionAll.mintSyFromToken)
     * @param inp Input params for compounding 
     * @param minSyOut minimum sy out acceptable
     */
    function compound(
        TokenInput calldata inp,
        uint256 minSyOut
    ) external returns (uint256 netSyOut);

    function readStrategyData() external view returns (StrategyData memory strategyData);

    function setSpecs(TradingSpecs calldata _specs) external;
}

