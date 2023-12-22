// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

interface IPlennyLocking {

    function totalVotesLocked() external view returns (uint256);

    function govLockReward() external view returns (uint256);

    function getUserVoteCountAtBlock(address account, uint blockNumber) external view returns (uint256);

    function getUserDelegatedVoteCountAtBlock(address account, uint blockNumber) external view returns (uint256);

    function checkDelegationAtBlock(address account, uint blockNumber) external view returns (bool);

    function getTotalVoteCountAtBlock(uint256 blockNumber) external view returns (uint256);

    function delegatedVotesCount(address account) external view returns (uint256);

    function userPlennyLocked(address user) external view returns (uint256);

    function checkDelegation(address addr) external view returns (bool);
}
