// SPDX-License-Identifier: MIT LICENSE
pragma solidity ^0.8.0;

interface IPABStake {
    // struct to store a pabstake's token, owner, and earning values
    struct PeekABooNormalStaked {
        uint256 tokenId;
        uint256 value;
        address owner;
    }

    function normalStakePeekABoos(uint16[] calldata tokenIds) external;

    /** CLAIMING / UNSTAKING */
    function claimMany(uint16[] calldata tokenIds) external;

    function unstakeMany(uint16[] calldata tokenIds) external;

    function getPeekABooValue(uint256[] calldata tokenIds)
        external
        view
        returns (uint256[] memory);

    function canClaimGhost(uint256 tokenId) external view returns (bool);
}

