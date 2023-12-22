


// SPDX-License-Identifier: MIT


pragma solidity ^0.7.1;

import {White} from "./White.sol";
import {Darwin721} from "./Darwin721.sol";



contract Character is Darwin721{
    constructor(string memory name, string memory symbol) Darwin721(name, symbol) {
        
    }
    
    function version() public pure returns (uint){
        return 2;
    }

    function burn(uint256 tokenId) public onlyOwner{
        _burn(tokenId);
    }

    function _beforeTokenTransfer(address from, address to, uint256 tokenId) internal override virtual {
        require(from == address(0), "Err: token transfer is BLOCKED");   
        super._beforeTokenTransfer(from, to, tokenId);  
    }

    function _mintByAdmin(uint256 tokenId, uint256 tag, address tokenOwner) public override reentrancyGuard onlyNFTAdmin {
        require(contractIsOpen, "Contract must be active");

        require(tag == 0, "character token tag must zero");
        require(msg.sender == nftAdmin(), "Only for nft admin");
        require(!_exists(tokenId), "ERC721: token already minted");
        require(balanceOf(tokenOwner) == 0, "Only 1 character for an address");
        mint(tokenOwner, tokenId, tag);        
    }

    function whiteAddr() public pure returns (address){
        return address(0);
    }

    function canFreeMint(address addr) public view returns (bool){
        return White(whiteAddr()).isWhite(addr);
    }
}

