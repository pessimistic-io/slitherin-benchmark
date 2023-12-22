// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IBribe {
    function getReward(uint256 tokenId, address[] memory tokens) external;
    function getRewardTokens() external view returns (address[] memory);
    function bribe(address token, uint amount) external;
}

