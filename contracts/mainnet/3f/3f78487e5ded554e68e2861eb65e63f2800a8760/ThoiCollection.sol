// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import "./console.sol";
import "./ERC721AQueryable.sol";
import "./Ownable.sol";
import "./ReentrancyGuard.sol";

contract ThoiCollectionAlpha is ERC721AQueryable, Ownable, ReentrancyGuard {
  uint32 public immutable _maxSupply;
  address public immutable _reserveAddress;
  
  bool public revealed = false;

  constructor(
    string memory name, 
    string memory symbol, 
    address reserveAddress,
    uint32 maxSupply
  ) ERC721A(name, symbol) {
    _reserveAddress = reserveAddress;
    _maxSupply = maxSupply;
  }

  function reserveMint(uint32 quantity) external payable nonReentrant {
    require(msg.sender == _reserveAddress, "not permitted to reserve");
    require((totalSupply() + quantity) <= _maxSupply, "reached max supply");
    _safeMint(msg.sender, quantity);
  }
  
  function reveal() external onlyOwner {
    revealed = true; 
  }
  
  // metadata URI
  string private _baseTokenURI;
  string private _placeholderTokenURI;
  function _baseURI() internal view virtual override returns (string memory) {
    return _baseTokenURI;
  }

  function setBaseURI(string calldata baseURI) external onlyOwner {
    _baseTokenURI = baseURI;
  }

  function setPlaceholderUri(string memory placeholderUri) external onlyOwner{
    _placeholderTokenURI = placeholderUri;
  }

  function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
    if(!_exists(tokenId)) revert URIQueryForNonexistentToken();
    if(revealed == false) {
        return _placeholderTokenURI;
    }
    
    string memory _tokenURI;
    _tokenURI = super.tokenURI(tokenId);
    return bytes(_tokenURI).length > 0 ? string(abi.encodePacked(_tokenURI, ".json")) : _placeholderTokenURI;
  }

  function withdraw() external onlyOwner nonReentrant {
    (bool success, ) = msg.sender.call{value: address(this).balance}("");
    require(success, "Transfer failed.");
  }
  
  function numberMinted(address owner) public view returns (uint256) {
    return _numberMinted(owner);
  }

  function getOwnershipData(uint256 tokenId) external view returns (TokenOwnership memory) {
    return _ownershipOf(tokenId);
  }

}

