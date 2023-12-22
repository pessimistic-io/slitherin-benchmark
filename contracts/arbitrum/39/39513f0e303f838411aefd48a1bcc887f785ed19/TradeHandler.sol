// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {ITradingModule, Trade} from "./ITradingModule.sol";
import {nProxy} from "./nProxy.sol";

/// @notice TradeHandler is an internal library to be compiled into StrategyVaults to interact
/// with the TradeModule and execute trades
library TradeHandler {

    /// @notice Can be used to delegate call to the TradingModule's implementation in order to execute
    /// a trade.
    function _executeTradeWithDynamicSlippage(
        Trade memory trade,
        uint16 dexId,
        ITradingModule tradingModule,
        uint32 dynamicSlippageLimit
    ) internal returns (uint256 amountSold, uint256 amountBought) {
        (bool success, bytes memory result) = nProxy(payable(address(tradingModule))).getImplementation()
            .delegatecall(abi.encodeWithSelector(
                ITradingModule.executeTradeWithDynamicSlippage.selector,
                dexId, trade, dynamicSlippageLimit
            )
        );
        require(success);
        (amountSold, amountBought) = abi.decode(result, (uint256, uint256));
    }

    /// @notice Can be used to delegate call to the TradingModule's implementation in order to execute
    /// a trade.
    function _executeTrade(
        Trade memory trade,
        uint16 dexId,
        ITradingModule tradingModule
    ) internal returns (uint256 amountSold, uint256 amountBought) {
        (bool success, bytes memory result) = nProxy(payable(address(tradingModule))).getImplementation()
            .delegatecall(abi.encodeWithSelector(ITradingModule.executeTrade.selector, dexId, trade));
        require(success);
        (amountSold, amountBought) = abi.decode(result, (uint256, uint256));
    }
}

