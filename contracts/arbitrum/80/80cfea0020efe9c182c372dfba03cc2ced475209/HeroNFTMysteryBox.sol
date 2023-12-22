// SPDX-License-Identifier: MIT
// DreamIdol Contracts (HeroNFTMysteryBox.sol)

pragma solidity ^0.8.0;

import "./MysteryBoxBase.sol";

contract HeroNFTMysteryBox is MysteryBoxBase
{    
    function getName() external virtual override returns(string memory)
    {
        return "Hero NFT Mystery Box";
    }
}
