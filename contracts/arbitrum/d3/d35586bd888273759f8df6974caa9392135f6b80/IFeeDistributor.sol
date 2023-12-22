// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IFeeDistributor {
    function getReward(uint256 tokenId, address[] memory tokens) external;
    function getRewardTokens() external view returns (address[] memory);
}

