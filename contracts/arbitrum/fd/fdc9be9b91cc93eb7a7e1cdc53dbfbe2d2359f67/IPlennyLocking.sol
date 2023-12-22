// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

interface IPlennyLocking {

    function totalVotesLocked() external view returns (uint256);

    function govLockReward() external view returns (uint256);

    function getUserVoteCountAtBlock(address account, uint blockNumber) external view returns (uint256);

    function getTotalVoteCountAtBlock(uint256 blockNumber) external view returns (uint256);
}
