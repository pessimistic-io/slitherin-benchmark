// SPDX-License-Identifier: agpl-3.0
pragma solidity >=0.7.0;

interface IStrategyVault {
    struct StrategyTradeParams {
        uint256 lowerSqrtPrice;
        uint256 upperSqrtPrice;
        uint256 deadline;
    }

    function deposit(
        uint256 _strategyId,
        uint256 _strategyTokenAmount,
        address _recepient,
        uint256 _maxMarginAmount,
        bool isQuoteMode,
        StrategyTradeParams memory _tradeParams
    ) external returns (uint256 finalDepositMargin);
}

