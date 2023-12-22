// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

interface IOpenTradesPnlFeed {
    function nextEpochValuesRequestCount() external view returns (uint256);

    function newOpenPnlRequestOrEpoch() external;
}

