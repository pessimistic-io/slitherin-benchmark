// SPDX-License-Identifier: MIT
// 
//       ___           ___           ___           ___                                                                                   
//      /\__\         /\  \         /\__\         /\  \                                                                                  
//     /::|  |        \:\  \       /:/  /         \:\  \                                                                                 
//    /:|:|  |         \:\  \     /:/  /           \:\  \                                                                                
//   /:/|:|  |__       /::\  \   /:/  /  ___       /::\  \                                                                               
//  /:/ |:| /\__\     /:/\:\__\ /:/__/  /\__\     /:/\:\__\                                                                              
//  \/__|:|/:/  /    /:/  \/__/ \:\  \ /:/  /    /:/  \/__/                                                                              
//      |:/:/  /    /:/  /       \:\  /:/  /    /:/  /                                                                                   
//      |::/  /     \/__/         \:\/:/  /     \/__/                                                                                    
//      /:/  /                     \::/  /                                                                                               
//      \/__/                       \/__/                                                                                                
//       ___           ___       ___           ___           ___           ___           ___           ___                       ___     
//      /\  \         /\__\     /\  \         /\  \         /\__\         /\  \         /\__\         /\  \          ___        /\__\    
//     /::\  \       /:/  /    /::\  \       /::\  \       /:/  /        /::\  \       /:/  /        /::\  \        /\  \      /::|  |   
//    /:/\:\  \     /:/  /    /:/\:\  \     /:/\:\  \     /:/__/        /:/\:\  \     /:/__/        /:/\:\  \       \:\  \    /:|:|  |   
//   /::\~\:\__\   /:/  /    /:/  \:\  \   /:/  \:\  \   /::\__\____   /:/  \:\  \   /::\  \ ___   /::\~\:\  \      /::\__\  /:/|:|  |__ 
//  /:/\:\ \:|__| /:/__/    /:/__/ \:\__\ /:/__/ \:\__\ /:/\:::::\__\ /:/__/ \:\__\ /:/\:\  /\__\ /:/\:\ \:\__\  __/:/\/__/ /:/ |:| /\__\
//  \:\~\:\/:/  / \:\  \    \:\  \ /:/  / \:\  \  \/__/ \/_|:|~~|~    \:\  \  \/__/ \/__\:\/:/  / \/__\:\/:/  / /\/:/  /    \/__|:|/:/  /
//   \:\ \::/  /   \:\  \    \:\  /:/  /   \:\  \          |:|  |      \:\  \            \::/  /       \::/  /  \::/__/         |:/:/  / 
//    \:\/:/  /     \:\  \    \:\/:/  /     \:\  \         |:|  |       \:\  \           /:/  /        /:/  /    \:\__\         |::/  /  
//     \::/__/       \:\__\    \::/  /       \:\__\        |:|  |        \:\__\         /:/  /        /:/  /      \/__/         /:/  /   
//      ~~            \/__/     \/__/         \/__/         \|__|         \/__/         \/__/         \/__/                     \/__/    
//       ___           ___       ___           ___                                                                                       
//      /\  \         /\__\     /\__\         /\  \                                                                                      
//     /::\  \       /:/  /    /:/  /        /::\  \                                                                                     
//    /:/\:\  \     /:/  /    /:/  /        /:/\:\  \                                                                                    
//   /:/  \:\  \   /:/  /    /:/  /  ___   /::\~\:\__\                                                                                   
//  /:/__/ \:\__\ /:/__/    /:/__/  /\__\ /:/\:\ \:|__|                                                                                  
//  \:\  \  \/__/ \:\  \    \:\  \ /:/  / \:\~\:\/:/  /                                                                                  
//   \:\  \        \:\  \    \:\  /:/  /   \:\ \::/  /                                                                                   
//    \:\  \        \:\  \    \:\/:/  /     \:\/:/  /                                                                                    
//     \:\__\        \:\__\    \::/  /       \::/__/                                                                                     
//      \/__/         \/__/     \/__/         ~~                                                                                         
// 
pragma solidity ^0.8.13;

import "./ERC721URIStorage.sol";
import "./Counters.sol";

contract Fish is ERC721URIStorage {
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;
    address public owner; 
    string public _baseTokenURI;
    bool public mintable = false;

    modifier only_owner() {
        require(msg.sender == owner, "You are not the owner");
        _;
    }

    modifier mintable_active() {
        require(mintable == true, "Minting is not allowed");
        _;
    }

    constructor(
        string memory baseTokenURI
    ) ERC721("Fish", "FISH") {
         _baseTokenURI = baseTokenURI;
        owner = msg.sender;
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return _baseTokenURI;
    }

    function mintFish(string memory tokenURI)
        public
        mintable_active
        returns (uint256)
    {
        _tokenIds.increment();

        uint256 newItemId = _tokenIds.current();
        _mint(msg.sender, newItemId);
        _setTokenURI(newItemId, tokenURI);

        return newItemId;
    }

    function mintable_switch()
        public
        only_owner
    {
        mintable = !mintable;
    }

    function base_token_URI_set(string memory base_token_URI)
        public 
        only_owner
        {
             _baseTokenURI = base_token_URI;
        }

    function change_owner(address new_owner)
        public
        only_owner
    {
        owner = new_owner;
    }
    
        
}
