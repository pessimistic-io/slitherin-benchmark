// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0;

interface IMockAggregatorInterface {
    function setAnswer(int256 answer) external;

    event AnswerUpdated(
        int256 indexed current,
        uint256 indexed roundId,
        uint256 updatedAt
    );
}

