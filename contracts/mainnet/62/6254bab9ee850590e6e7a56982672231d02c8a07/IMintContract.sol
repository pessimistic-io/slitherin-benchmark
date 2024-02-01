// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IMintContract {
    function generateURI(uint256 citizenId) external view returns (string memory);
    function calculateRewardRate(uint256 identityId, uint256 vaultId) external view returns (uint256);
}

