// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.13;

interface ICaller {
    function fulfillRNG(bytes32 _requestId, uint256[] memory _randomNumbers) external;
}

