// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./Ownable.sol";
import "./IMockAggregatorInterface.sol";
import "./MockAggregatorV3Interface.sol";

contract MockAggregator is IMockAggregatorInterface, Ownable {
    address public aggregatorInterface;

    constructor(address _aggregatorInterface) {
        aggregatorInterface = _aggregatorInterface;
    }

    function setAnswer(int256 answer) external override onlyOwner {
        MockAggregatorV3Interface(aggregatorInterface).setPrice(answer);
        emit AnswerUpdated(answer, 1, block.timestamp);
    }
}

