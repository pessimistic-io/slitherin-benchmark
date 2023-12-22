// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

interface IMeson {
    function postSwapFromContract(uint256 encodedSwap, bytes32 r, bytes32 yParityAndS, uint200 postingValue, address contractAddress) external;
    function cancelSwap(uint256 encodedSwap) external;
}

