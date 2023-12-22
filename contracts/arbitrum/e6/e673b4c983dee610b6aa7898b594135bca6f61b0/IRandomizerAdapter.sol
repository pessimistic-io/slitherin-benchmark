// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IRandomizerAdapter {
    function requestRandomNumber(uint256 raffleId) external returns (uint256);

    function randomizerCallback(uint256 _id, bytes32 _value) external;
}

