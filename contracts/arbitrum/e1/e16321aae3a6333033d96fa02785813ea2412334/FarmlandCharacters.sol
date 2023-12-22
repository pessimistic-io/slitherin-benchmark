// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./FarmlandCollectible.sol";

contract FarmlandCharacters is FarmlandCollectible {

    constructor ()
    ERC721("Farmland Characters", "CHARACTERS")
    {
        isPaused(true);  // Start the contract in paused model
    }

    function storeTraits(uint256 id) 
        internal
        override
    {
        require( !_exists(id),                                                  "Traits can be generated only once");
        CollectibleTraits storage collectibleTrait = collectibleTraits[id];     // Shortcut accessor to store Collectible traits on chain
        collectibleTrait.trait1 = random(80, msg.sender) + 20;                  // stamina
        collectibleTrait.trait2 = random(80, msg.sender) + 20;                  // strength
        collectibleTrait.trait3 = random(80, msg.sender) + 20;                  // speed
        collectibleTrait.trait4 = random(80, msg.sender) + 20;                  // courage
        collectibleTrait.trait5 = random(80, msg.sender) + 20;                  // intelligence
    }
}
