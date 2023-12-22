// SPDX-License-Identifier: MIT
pragma solidity >=0.6.2 <0.7.0;

import "./IERC721Metadata.sol";

struct CollectibleTraits {uint256 expiryDate; uint256 trait1; uint256 trait2; uint256 trait3; uint256 trait4; uint256 trait5;}

abstract contract IFarmlandCollectible is IERC721Metadata {

    /**
     * @dev PUBLIC: Stores the key traits for Farmland Collectibles
     */
    mapping(uint256 => CollectibleTraits) public collectibleTraits;

}
