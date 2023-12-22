// SPDX-License-Identifier: MIT
// ERC721A Contracts v4.0.0
// Creator: Chiru Labs

pragma solidity ^0.8.4;


interface IERC721A {
   
    error ApprovalCallerNotOwnerNorApproved();

   
    error ApprovalQueryForNonexistentToken();

   
    error ApproveToCaller();

 
    error ApprovalToCurrentOwner();

   
    error BalanceQueryForZeroAddress();

   
    error MintToZeroAddress();

    
    error MintZeroQuantity();

  
    error OwnerQueryForNonexistentToken();

    
    error TransferCallerNotOwnerNorApproved();

   
    error TransferFromIncorrectOwner();

   
    error TransferToNonERC721ReceiverImplementer();

   
    error TransferToZeroAddress();

    
    error URIQueryForNonexistentToken();

    struct TokenOwnership {
       
        address addr;
      
        uint64 startTimestamp;
        
        bool burned;
    }

   
    function totalSupply() external view returns (uint256);

    
    function supportsInterface(bytes4 interfaceId) external view returns (bool);

   
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);

  
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);

    
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    
    function balanceOf(address owner) external view returns (uint256 balance);

  
    function ownerOf(uint256 tokenId) external view returns (address owner);

   
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes calldata data
    ) external;

    
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) external;

   
    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) external;

    
    function approve(address to, uint256 tokenId) external;

   
    function setApprovalForAll(address operator, bool _approved) external;

    
    function getApproved(uint256 tokenId) external view returns (address operator);

   
    function isApprovedForAll(address owner, address operator) external view returns (bool);

    
    function name() external view returns (string memory);

   
    function symbol() external view returns (string memory);

    
    function tokenURI(uint256 tokenId) external view returns (string memory);
}
