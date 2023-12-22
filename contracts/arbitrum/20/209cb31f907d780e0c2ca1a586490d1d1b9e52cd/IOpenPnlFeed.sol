// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IOpenPnlFeed{
    function nextEpochValuesRequestCount() external view returns(uint256);
    function newOpenPnlRequestOrEpoch() external;
}

interface IAddOpenPnlFeedFund{
    function addOpenPnlFeedFund() external returns (uint256);
}


