// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

interface IFastPriceFeed {
    function description() external view returns (string memory);

    function getRoundData(uint80 roundId) external view returns (uint80, uint256, uint256, uint256, uint80);

    function latestAnswer() external view returns (uint256);

    function latestRound() external view returns (uint80);

    function setLatestAnswer(uint256 _answer) external;

    function latestSynchronizedPrice() external view returns (
      uint256 answer,
      uint256 updatedAt
    );
}
