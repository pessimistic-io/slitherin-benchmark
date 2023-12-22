// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

interface IGemChest {

    function safeMint(address to, uint256 tokenId) external; 

    function burn(uint256 tokenId) external;

    function ownerOf(uint256 tokenId) external view returns (address);
    
    function approve(address to, uint256 tokenId) external;
    
    function transferFrom(address _from, address _to, uint256 _tokenId) external;
    
    function safeTransferFrom(address from, address to, uint tokenId) external;

    function safeTransferFrom(address from, address to, uint tokenId, bytes memory data) external;
   

}
