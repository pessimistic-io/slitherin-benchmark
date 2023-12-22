// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IOpenTradesPnlFeed {
    function newOpenPnlRequest() external;

    function isCalculating() external view returns (bool);
}

