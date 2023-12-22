// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

interface IOpenTradesPnlFeed{
    function nextEpochValuesRequestCount() external view returns(uint);
    function newOpenPnlRequestOrEpoch() external;
}
