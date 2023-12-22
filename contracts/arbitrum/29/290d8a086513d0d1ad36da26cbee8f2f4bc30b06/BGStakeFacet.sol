// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

// Storage imports
import { WithModifiers } from "./LibStorage.sol";
import { Errors } from "./Errors.sol";

// Library imports
import { LibStakeUtils } from "./LibStakeUtils.sol";

// Contract imports
import { ReentrancyGuard } from "./ReentrancyGuard.sol";
import { ERC721Holder } from "./ERC721Holder.sol";

contract BGStakeFacet is WithModifiers, ReentrancyGuard, ERC721Holder {
    event BulkStakeBattlefly(uint256[] tokenIds, uint256[] tokenTypes, address indexed user, uint256 totalMagicAmount);
    event BulkUnstakeBattlefly(
        uint256[] tokenIds,
        uint256[] tokenTypes,
        address indexed user,
        uint256 totalMagicAmount
    );

    /**
     * @dev Stakes a soulbound token from the soulbound contract
     */
    function stakeSoulbound(address owner, uint256 tokenId) external onlySoulbound notPaused {
        LibStakeUtils.stakeSoulbound(owner, tokenId);
    }

    /**
     * @dev Stakes a list of battleflies of the origin (0) or soulbound (1) types
     */
    function bulkStakeBattlefly(uint256[] memory tokenIds, uint256[] memory tokenTypes) external notPaused {
        LibStakeUtils.bulkStakeBattlefly(tokenIds, tokenTypes);
    }

    /**
     * @dev Unstakes a list of battleflies of the origin (0) or soulbound (1) types
     */
    function bulkUnstakeBattlefly(
        uint256[] memory tokenIds,
        uint256[] memory tokenTypes,
        uint256[] memory battleflyStages,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external notPaused {
        LibStakeUtils.bulkUnstakeBattlefly(tokenIds, tokenTypes, battleflyStages, v, r, s);
    }

    /**
     * @dev returns a list of battleflies of the origin (0) or soulbound (1) types, owned by the provided address
     */
    function stakingBattlefliesOfOwner(address owner, uint256 tokenType) external view returns (uint256[] memory) {
        return LibStakeUtils.stakingBattlefliesOfOwner(owner, tokenType);
    }

    /**
     * @dev returns the balance of battleflies of the origin (0) or soulbound (1) types, from the provided address
     */
    function balanceOf(address owner, uint256 tokenType) external view returns (uint256) {
        return LibStakeUtils.balanceOf(owner, tokenType);
    }

    /**
     * @dev returns the owner of a specific battlefly of the origin (0) or soulbound (1) type
     */
    function ownerOf(uint256 tokenId, uint256 tokenType) external view returns (address owner) {
        return LibStakeUtils.ownerOf(tokenId, tokenType);
    }
}

