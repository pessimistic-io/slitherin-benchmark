// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./ITradingStorage.sol";


library TradeUtils {

    function setTradeLastUpdated(
        address _callbacks,
        address trader,
        uint256 pairIndex,
        uint256 index,
        ITradingCallbacks01.TradeType _type,
        uint256 blockNumber
    ) external {
        uint32 b = uint32(blockNumber);
        ITradingCallbacks01 callbacks = ITradingCallbacks01(_callbacks);
        callbacks.setTradeLastUpdated(
            ITradingCallbacks01.SimplifiedTradeId(trader, pairIndex, index, _type),
            ITradingCallbacks01.LastUpdated(b, b, b, b)
        );
    }

    function setSlLastUpdated(
        address _callbacks,
        address trader,
        uint256 pairIndex,
        uint256 index,
        ITradingCallbacks01.TradeType _type,
        uint256 blockNumber
    ) external {
        (
            ITradingCallbacks01 callbacks,
            ITradingCallbacks01.LastUpdated memory l,
            ITradingCallbacks01.SimplifiedTradeId memory id
        ) = _getTradeLastUpdated(_callbacks, trader, pairIndex, index, _type);

        l.sl = uint32(blockNumber);
        callbacks.setTradeLastUpdated(id, l);
    }

    function setTpLastUpdated(
        address _callbacks,
        address trader,
        uint256 pairIndex,
        uint256 index,
        ITradingCallbacks01.TradeType _type,
        uint256 blockNumber
    ) external {
        (
            ITradingCallbacks01 callbacks,
            ITradingCallbacks01.LastUpdated memory l,
            ITradingCallbacks01.SimplifiedTradeId memory id
        ) = _getTradeLastUpdated(_callbacks, trader, pairIndex, index, _type);

        l.tp = uint32(blockNumber);
        callbacks.setTradeLastUpdated(id, l);
    }

    function setLimitLastUpdated(
        address _callbacks,
        address trader,
        uint256 pairIndex,
        uint256 index,
        ITradingCallbacks01.TradeType _type,
        uint256 blockNumber
    ) external {
        (
            ITradingCallbacks01 callbacks,
            ITradingCallbacks01.LastUpdated memory l,
            ITradingCallbacks01.SimplifiedTradeId memory id
        ) = _getTradeLastUpdated(_callbacks, trader, pairIndex, index, _type);

        l.limit = uint32(blockNumber);
        callbacks.setTradeLastUpdated(id, l);
    }

    function isTpInTimeout(
        address _callbacks,
        ITradingCallbacks01.SimplifiedTradeId memory id,
        uint256 currentBlock
    ) external view returns (bool) {
        (ITradingCallbacks01 callbacks, ITradingCallbacks01.LastUpdated memory l, ) = _getTradeLastUpdated(
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
        ITradingCallbacks01.SimplifiedTradeId memory id,
        uint256 currentBlock
    ) external view returns (bool) {
        (ITradingCallbacks01 callbacks, ITradingCallbacks01.LastUpdated memory l, ) = _getTradeLastUpdated(
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
        ITradingCallbacks01.SimplifiedTradeId memory id,
        uint256 currentBlock
    ) external view returns (bool) {
        (ITradingCallbacks01 callbacks, ITradingCallbacks01.LastUpdated memory l, ) = _getTradeLastUpdated(
            _callbacks,
            id.trader,
            id.pairIndex,
            id.index,
            id.tradeType
        );

        return currentBlock < uint256(l.limit) + callbacks.canExecuteTimeout();
    }

    function getTradeLastUpdated(
        address _callbacks,
        address trader,
        uint256 pairIndex,
        uint256 index,
        ITradingCallbacks01.TradeType _type
    )
        external
        view
        returns (
            ITradingCallbacks01,
            ITradingCallbacks01.LastUpdated memory,
            ITradingCallbacks01.SimplifiedTradeId memory
        )
    {
        return _getTradeLastUpdated(_callbacks, trader, pairIndex, index, _type);
    }

    function _getTradeLastUpdated(
        address _callbacks,
        address trader,
        uint256 pairIndex,
        uint256 index,
        ITradingCallbacks01.TradeType _type
    )
        internal
        view
        returns (
            ITradingCallbacks01,
            ITradingCallbacks01.LastUpdated memory,
            ITradingCallbacks01.SimplifiedTradeId memory
        )
    {
        ITradingCallbacks01 callbacks = ITradingCallbacks01(_callbacks);
        ITradingCallbacks01.LastUpdated memory l = callbacks.tradeLastUpdated(trader, pairIndex, index, _type);

        return (callbacks, l, ITradingCallbacks01.SimplifiedTradeId(trader, pairIndex, index, _type));
    }
}

