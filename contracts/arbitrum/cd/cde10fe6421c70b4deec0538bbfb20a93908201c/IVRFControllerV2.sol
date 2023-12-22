// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

interface IVRFControllerV2 {
    function generateRequest(uint8 _rngCount) external returns (uint256);
}

