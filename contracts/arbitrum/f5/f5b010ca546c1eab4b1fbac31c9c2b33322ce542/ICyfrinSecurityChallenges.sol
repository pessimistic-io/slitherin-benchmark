// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

interface ICyfrinSecurityChallenges {
    function mintNft(address receiver) external returns (uint256);

    function addChallenge(address challengeContract) external returns (uint256);
}

