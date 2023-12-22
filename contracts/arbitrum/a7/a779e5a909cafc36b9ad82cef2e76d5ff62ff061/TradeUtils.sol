// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./IGNSTradingCallbacks.sol";

/**
 * @custom:version 6.4.2
 */
library TradeUtils {
    function _getTradeLastUpdated(
        address _callbacks,
        address trader,
        uint256 pairIndex,
        uint256 index,
        IGNSTradingCallbacks.TradeType _type
    )
        internal
        view
        returns (
            IGNSTradingCallbacks,
            IGNSTradingCallbacks.LastUpdated memory,
            IGNSTradingCallbacks.SimplifiedTradeId memory
        )
    {
        IGNSTradingCallbacks callbacks = IGNSTradingCallbacks(_callbacks);
        IGNSTradingCallbacks.LastUpdated memory l = callbacks.getTradeLastUpdated(trader, pairIndex, index, _type);

        return (callbacks, l, IGNSTradingCallbacks.SimplifiedTradeId(trader, pairIndex, index, _type));
    }

    function setTradeLastUpdated(
        address _callbacks,
        address trader,
        uint256 pairIndex,
        uint256 index,
        IGNSTradingCallbacks.TradeType _type,
        uint256 blockNumber
    ) external {
        uint32 b = uint32(blockNumber);
        IGNSTradingCallbacks callbacks = IGNSTradingCallbacks(_callbacks);
        callbacks.setTradeLastUpdated(
            IGNSTradingCallbacks.SimplifiedTradeId(trader, pairIndex, index, _type),
            IGNSTradingCallbacks.LastUpdated(b, b, b, b)
        );
    }

    function setSlLastUpdated(
        address _callbacks,
        address trader,
        uint256 pairIndex,
        uint256 index,
        IGNSTradingCallbacks.TradeType _type,
        uint256 blockNumber
    ) external {
        (
            IGNSTradingCallbacks callbacks,
            IGNSTradingCallbacks.LastUpdated memory l,
            IGNSTradingCallbacks.SimplifiedTradeId memory id
        ) = _getTradeLastUpdated(_callbacks, trader, pairIndex, index, _type);

        l.sl = uint32(blockNumber);
        callbacks.setTradeLastUpdated(id, l);
    }

    function setTpLastUpdated(
        address _callbacks,
        address trader,
        uint256 pairIndex,
        uint256 index,
        IGNSTradingCallbacks.TradeType _type,
        uint256 blockNumber
    ) external {
        (
            IGNSTradingCallbacks callbacks,
            IGNSTradingCallbacks.LastUpdated memory l,
            IGNSTradingCallbacks.SimplifiedTradeId memory id
        ) = _getTradeLastUpdated(_callbacks, trader, pairIndex, index, _type);

        l.tp = uint32(blockNumber);
        callbacks.setTradeLastUpdated(id, l);
    }

    function setLimitMaxSlippageP(
        address _callbacks,
        address trader,
        uint256 pairIndex,
        uint256 index,
        uint256 maxSlippageP
    ) external {
        require(maxSlippageP <= type(uint40).max, "OVERFLOW");
        IGNSTradingCallbacks(_callbacks).setTradeData(
            IGNSTradingCallbacks.SimplifiedTradeId(trader, pairIndex, index, IGNSTradingCallbacks.TradeType.LIMIT),
            IGNSTradingCallbacks.TradeData(uint40(maxSlippageP), 0, 0)
        );
    }
}

