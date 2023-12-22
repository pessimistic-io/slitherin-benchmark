// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "./ReentrancyGuard.sol";

import "./ERC721A.sol";
import "./ManagerModifier.sol";

contract Reactor is ERC721A, ReentrancyGuard, ManagerModifier {
  string public defaultBaseURI;

  //=======================================
  // Events
  //=======================================
  event MintedFor(address minter, uint256 quantity);
  event Burned(address burner, uint256 tokenId);

  //=======================================
  // Constructor
  //=======================================
  constructor(address _manager)
    ERC721A("Reactor", "REACTOR")
    ManagerModifier(_manager)
  {}

  //=======================================
  // External
  //=======================================
  function mintFor(address _for, uint256 _quantity)
    external
    nonReentrant
    onlyMinter
    returns (uint256)
  {
    emit MintedFor(_for, _quantity);

    // Mint
    return _safeMint(_for, _quantity);
  }

  function burn(uint256 _tokenId) external nonReentrant {
    // Check if sender owns token
    require(
      ownerOf(_tokenId) == msg.sender,
      "Reactor: You do not own this token"
    );

    // Burn
    _burn(_tokenId);

    emit Burned(msg.sender, _tokenId);
  }

  function tokenURI(uint256) public view override returns (string memory) {
    return defaultBaseURI;
  }

  //=======================================
  // Admin
  //=======================================
  function setBaseURI(string calldata _baseUri) internal onlyAdmin {
    defaultBaseURI = _baseUri;
  }
}

