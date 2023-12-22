//SPDX-License-Identifier: Unlicense
pragma solidity >=0.6.0;

interface IBattleflyStaker {
    function stakingBattlefliesOfOwner(address user) external view returns (uint256[] memory);

    function bulkStakeBattlefly(uint256[] memory tokenIds) external;

    function bulkUnstakeBattlefly(
        uint256[] memory tokenIds,
        uint256[] memory battleflyStages,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    function balanceOf(address owner) external view returns (uint256);

    function ownerOf(uint256 tokenId) external view returns (address owner);
}

