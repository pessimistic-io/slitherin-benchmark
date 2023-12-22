// SPDX-License-Identifier: agpl-3.0
pragma solidity >=0.7.0;

import "./DataType.sol";

interface IPredyTradeCallback {
    function predyTradeCallback(DataType.TradeResult memory _tradeResult, bytes calldata data)
        external
        returns (int256);
}

