//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./AggregatorInterface.sol";

interface IOracle is AggregatorInterface {
    function submit(uint256 roundId, int256 price) external;
}

