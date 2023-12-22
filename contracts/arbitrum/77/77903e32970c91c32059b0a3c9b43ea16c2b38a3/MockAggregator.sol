// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "./IAggregatorV3Interface.sol";

contract MockAggregator is IAggregatorV3Interface {
    int256 public price;

    constructor(int256 _price) {
        price = _price;
    }

    function latestRoundData()
        external
        view
        override
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return (0, price, 0, block.timestamp, 0);
    }
}

