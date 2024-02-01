// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "./Strings.sol";
import "./ERC721.sol";

abstract contract ERC721HexURI is ERC721 {
  using Strings for uint256;

  function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
    string memory base = _baseURI();
    return bytes(base).length > 0 ? string(abi.encodePacked(base, tokenId.toHexString(32))) : "";
  }
}

