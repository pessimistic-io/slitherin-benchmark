// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IGaugeV2 {
    function getReward(uint256 tokenId, address[] memory tokens) external;
    function earned(address token, uint tokenId) external view returns (uint reward);
}

