


// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

pragma experimental ABIEncoderV2;

import {Darwin721} from "./Darwin721.sol";

contract Darwin721SBT is  Darwin721{
    constructor(string memory name, string memory symbol) Darwin721(name, symbol) {
        
    }
    
    function _beforeTokenTransfer(address from, address to, uint256 tokenId) internal override virtual {
        require(from == address(0), "Err: token transfer is BLOCKED");   
        super._beforeTokenTransfer(from, to, tokenId);  
    }

    function mintTo(address owner, uint256 tokenId, uint256 tokenTag) public onlyOwner {
        mint(owner, tokenId, tokenTag);
    }
}


