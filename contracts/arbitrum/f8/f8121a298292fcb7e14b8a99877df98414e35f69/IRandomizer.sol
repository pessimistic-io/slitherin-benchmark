//SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;
interface IRandomizer {
    // Returns a request ID for a random number. This is unique.
    function requestRandomNumber() external returns (uint256);

    // Returns the random number for the given request ID. Will revert
    // if the random is not ready.
    function revealRandomNumber(
        uint256 _requestId
    ) external view returns (uint256);

    // Returns if the random number for the given request ID is ready or not. Call
    // before calling revealRandomNumber.
    function isRandomReady(uint256 _requestId) external view returns (bool);
}

