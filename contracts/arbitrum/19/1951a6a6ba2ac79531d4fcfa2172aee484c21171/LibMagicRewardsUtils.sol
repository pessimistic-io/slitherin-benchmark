// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.17;

// Library imports
import { MerkleProof } from "./MerkleProof.sol";

// Storage imports
import { LibStorage, WastelandStorage } from "./LibStorage.sol";
import { ERC721BaseStorage } from "./ERC721BaseStorage.sol";

library LibMagicRewardsUtils {
    using ERC721BaseStorage for ERC721BaseStorage.Layout;

    error WastelandsAlreadyMinted();
    error InvalidSignature();

    function ws() internal pure returns (WastelandStorage storage) {
        return LibStorage.wastelandStorage();
    }

    function claimableMagicReward(uint256 landId) internal view returns (uint256) {
        return ws().magicRewardsPerLand - ws().rewardsWithdrawnPerLand[landId];
    }
}

