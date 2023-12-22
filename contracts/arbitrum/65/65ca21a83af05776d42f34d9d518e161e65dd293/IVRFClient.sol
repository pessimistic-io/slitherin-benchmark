// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IVRFClient {
    function rawFulfillRandomWords(uint256 requestId, uint256[] memory randomWords) external;
}
