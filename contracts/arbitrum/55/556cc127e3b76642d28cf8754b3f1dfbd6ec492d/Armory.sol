


// SPDX-License-Identifier: MIT


pragma solidity ^0.7.1;

import {Darwin721} from "./Darwin721.sol";



contract Armory is Darwin721{
    constructor(string memory name, string memory symbol) Darwin721(name, symbol) {
        
    }
    
    function version() public pure returns (uint){
        return 1;
    }

    

    function reforge(uint256 token1, uint256 token2, uint256 newTokenId) public {
        require(contractIsOpen, "Contract must be active");

        require(ownerOf(token1) == msg.sender && ownerOf(token1) == ownerOf(token2), "token owner check error");

        require(tokenTag(token1) != 0 && tokenTag(token1) == tokenTag(token2), "2 nft must the same tag");

        uint256 tokenTag = tokenTag(token1);

        _burn(token1);

        _burn(token2);
    
        mint(msg.sender, newTokenId, tokenTag);
    }

    function _mintByAdmin(uint256 tokenId, uint256 tag, address tokenOwner) override public reentrancyGuard onlyNFTAdmin {
        require(contractIsOpen, "Contract must be active");

        require(msg.sender == nftAdmin(), "Only for nft admin");
        require(!_exists(tokenId), "ERC721: token already minted");

        require(tag > 100000, "token id check error");

        mint(tokenOwner, tokenId, tag);        
    }

}

