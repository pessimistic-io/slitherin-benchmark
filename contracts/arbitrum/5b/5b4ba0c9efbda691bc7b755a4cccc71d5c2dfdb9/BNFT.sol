
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Ownable.sol";
import "./ERC721.sol";

contract BNFT is ERC721, Ownable {
    uint256 public totalSupply = 0;
    constructor(
        string memory name_,
        string memory symbol_
    ) ERC721(name_, symbol_) {
    }
    
    function mint() external payable  {
        ERC721._mint(msg.sender, totalSupply++);
    }
    
    function mintAddress(address to) external payable{
        ERC721._mint(to, totalSupply++);
    }
    
    function mintAmount(address to, uint256 amount) external payable {
        for (uint256 i=0; i<amount; i++) 
        {
            ERC721._mint(to, totalSupply++);
        }
    }
}
