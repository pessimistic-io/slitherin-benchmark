// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ITradeEvent {
    function trade(uint8 source, address user, uint256 usd) external;

    function claimReward() external;

    function inProgress() external view returns (bool);
}

