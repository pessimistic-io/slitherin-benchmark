// SPDX-License-Identifier: MPS
pragma solidity ^0.8.3;

interface ILearnToEarnReward {
   
    struct ClaimHistory {
        address user;
        uint coinValue; // in wei
        uint learnTokenValue; // in wei
        uint timestamp;
    }
   
    function getClaimHistory(uint salt) external view returns(ClaimHistory memory);
    function getClaimIds(address user) external view returns(uint[] memory);
    function getClaimHistories(address user) external view returns(ClaimHistory[] memory);
    function claim(uint salt, uint coinValue, uint8 v, bytes32 r, bytes32 s) external;
}

