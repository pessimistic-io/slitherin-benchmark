// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IStakingRewards {
    function accountVoteShare(address account) external view returns (uint256);
}
