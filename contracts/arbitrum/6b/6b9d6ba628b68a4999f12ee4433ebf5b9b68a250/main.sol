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

pragma solidity ^0.8.9;

import "./ERC1155.sol";
import "./Ownable.sol";
import "./Pausable.sol";

contract ProofOfNTUTBlockchainMembership is ERC1155, Ownable, Pausable {

    string public name = "Proof Of NTUT Blockchain Membership";
    uint256 public mint_id = 0;
    uint256 public mint_amount = 1;
    bytes public mint_data = "";
    mapping ( uint256 => string) public uris;
    constructor( uint256 _tokenId, string memory _URI) ERC1155("") {
        uris[_tokenId] = _URI;
    }

    function setURI(uint256 _tokenId, string memory newuri) public onlyOwner {
        uris[_tokenId] = newuri;
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }
    

    function uri(uint256 _tokenId) override public view returns (string memory) {
        return uris[_tokenId];
    }

    function mint(address _account, uint256 _tokenId)
        public
        onlyOwner
    {
        _mint(_account, _tokenId, mint_amount, mint_data);
    }

    function multiMint(address[] memory to, uint256 _tokenId)
        public 
        onlyOwner
        {
        for (uint256 i = 0; i < to.length; i++) {

            _mint(to[i], _tokenId, mint_amount, mint_data);
        }
        }

    function _beforeTokenTransfer(address operator, address from, address to, uint256[] memory ids, uint256[] memory amounts, bytes memory data)
        internal
        whenNotPaused
        override
    {
        super._beforeTokenTransfer(operator, from, to, ids, amounts, data);
    }
}

