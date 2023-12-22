// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

interface IEACAggregatorProxy {

    function latestAnswer() external view returns (int256);

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80);

}

