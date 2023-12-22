// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

interface IVoteDashboard {
    struct VotedGrvInfo {
        uint256 totalVotedGrvAmount;
        uint256 totalVotedGrvRatio;
        uint256 myVotedGrvAmount;
        uint256 myVotedGrvRatio;
    }

    struct VotingStatus {
        string symbol;
        uint256 userWeight;
        uint256 poolVotedRate;
        uint256 fromGrvSupplyAPR;
        uint256 fromGrvBorrowAPR;
        uint256 toGrvSupplyAPR;
        uint256 toGrvBorrowAPR;
    }

    function votedGrvInfo(address user) external view returns (VotedGrvInfo memory);
    function votingStatus(address user) external view returns (VotingStatus[] memory);
}
