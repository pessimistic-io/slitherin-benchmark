// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./StorageInterfaceV5.sol";

library TradeUtils {
    function _getTradeLastUpdated(
        address _callbacks,
        address trader,
        uint pairIndex,
        uint index,
        TradingCallbacksV6_4.TradeType _type
    )
        internal
        view
        returns (
            TradingCallbacksV6_4,
            TradingCallbacksV6_4.LastUpdated memory,
            TradingCallbacksV6_4.SimplifiedTradeId memory
        )
    {
        TradingCallbacksV6_4 callbacks = TradingCallbacksV6_4(_callbacks);
        TradingCallbacksV6_4.LastUpdated memory l = callbacks.tradeLastUpdated(trader, pairIndex, index, _type);

        return (callbacks, l, TradingCallbacksV6_4.SimplifiedTradeId(trader, pairIndex, index, _type));
    }

    function getTradeLastUpdated(
        address _callbacks,
        address trader,
        uint pairIndex,
        uint index,
        TradingCallbacksV6_4.TradeType _type
    )
        external
        view
        returns (
            TradingCallbacksV6_4,
            TradingCallbacksV6_4.LastUpdated memory,
            TradingCallbacksV6_4.SimplifiedTradeId memory
        )
    {
        return _getTradeLastUpdated(_callbacks, trader, pairIndex, index, _type);
    }

    function setTradeLastUpdated(
        address _callbacks,
        address trader,
        uint pairIndex,
        uint index,
        TradingCallbacksV6_4.TradeType _type,
        uint blockNumber
    ) external {
        uint32 b = uint32(blockNumber);
        TradingCallbacksV6_4 callbacks = TradingCallbacksV6_4(_callbacks);
        callbacks.setTradeLastUpdated(
            TradingCallbacksV6_4.SimplifiedTradeId(trader, pairIndex, index, _type),
            TradingCallbacksV6_4.LastUpdated(b, b, b, b)
        );
    }

    function setSlLastUpdated(
        address _callbacks,
        address trader,
        uint pairIndex,
        uint index,
        TradingCallbacksV6_4.TradeType _type,
        uint blockNumber
    ) external {
        (
            TradingCallbacksV6_4 callbacks,
            TradingCallbacksV6_4.LastUpdated memory l,
            TradingCallbacksV6_4.SimplifiedTradeId memory id
        ) = _getTradeLastUpdated(_callbacks, trader, pairIndex, index, _type);

        l.sl = uint32(blockNumber);
        callbacks.setTradeLastUpdated(id, l);
    }

    function setTpLastUpdated(
        address _callbacks,
        address trader,
        uint pairIndex,
        uint index,
        TradingCallbacksV6_4.TradeType _type,
        uint blockNumber
    ) external {
        (
            TradingCallbacksV6_4 callbacks,
            TradingCallbacksV6_4.LastUpdated memory l,
            TradingCallbacksV6_4.SimplifiedTradeId memory id
        ) = _getTradeLastUpdated(_callbacks, trader, pairIndex, index, _type);

        l.tp = uint32(blockNumber);
        callbacks.setTradeLastUpdated(id, l);
    }

    function setLimitLastUpdated(
        address _callbacks,
        address trader,
        uint pairIndex,
        uint index,
        TradingCallbacksV6_4.TradeType _type,
        uint blockNumber
    ) external {
        (
            TradingCallbacksV6_4 callbacks,
            TradingCallbacksV6_4.LastUpdated memory l,
            TradingCallbacksV6_4.SimplifiedTradeId memory id
        ) = _getTradeLastUpdated(_callbacks, trader, pairIndex, index, _type);

        l.limit = uint32(blockNumber);
        callbacks.setTradeLastUpdated(id, l);
    }

    function isTpInTimeout(
        address _callbacks,
        TradingCallbacksV6_4.SimplifiedTradeId memory id,
        uint currentBlock
    ) external view returns (bool) {
        (TradingCallbacksV6_4 callbacks, TradingCallbacksV6_4.LastUpdated memory l, ) = _getTradeLastUpdated(
            _callbacks,
            id.trader,
            id.pairIndex,
            id.index,
            id.tradeType
        );

        return currentBlock < uint256(l.tp) + callbacks.canExecuteTimeout();
    }

    function isSlInTimeout(
        address _callbacks,
        TradingCallbacksV6_4.SimplifiedTradeId memory id,
        uint currentBlock
    ) external view returns (bool) {
        (TradingCallbacksV6_4 callbacks, TradingCallbacksV6_4.LastUpdated memory l, ) = _getTradeLastUpdated(
            _callbacks,
            id.trader,
            id.pairIndex,
            id.index,
            id.tradeType
        );

        return currentBlock < uint256(l.sl) + callbacks.canExecuteTimeout();
    }

    function isLimitInTimeout(
        address _callbacks,
        TradingCallbacksV6_4.SimplifiedTradeId memory id,
        uint currentBlock
    ) external view returns (bool) {
        (TradingCallbacksV6_4 callbacks, TradingCallbacksV6_4.LastUpdated memory l, ) = _getTradeLastUpdated(
            _callbacks,
            id.trader,
            id.pairIndex,
            id.index,
            id.tradeType
        );

        return currentBlock < uint256(l.limit) + callbacks.canExecuteTimeout();
    }

    function setTradeData(
        address _callbacks,
        address trader,
        uint pairIndex,
        uint index,
        TradingCallbacksV6_4.TradeType _type,
        uint maxSlippageP
    ) external {
        require(maxSlippageP < type(uint40).max, "OVERFLOW");
        TradingCallbacksV6_4 callbacks = TradingCallbacksV6_4(_callbacks);
        callbacks.setTradeData(
            TradingCallbacksV6_4.SimplifiedTradeId(trader, pairIndex, index, _type),
            TradingCallbacksV6_4.TradeData(uint40(maxSlippageP), 0)
        );
    }
}

