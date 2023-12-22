// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

interface IStake {
    struct Stake {
        uint256 tokenId;
        uint8 timeLevel;
        uint256 unlockTime;
        uint256 lastClaimTime;
    }

    function stakelist(address user, uint256 index) external view returns(Stake memory);

    function calculateReward(uint256 tokenId, uint8 timeLevel, uint256 lastClaimTime) external view returns(uint256);
}
