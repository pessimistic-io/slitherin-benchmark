// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import "./ERC721.sol";
import "./ERC721Enumerable.sol";
import "./ERC721Burnable.sol";
import "./Ownable.sol";

contract DIPXGenesisPass is ERC721, ERC721Enumerable, ERC721Burnable, Ownable {
  mapping(address => bool) public isMinter;

  constructor() ERC721("DIPXGenesisPass", "DGP") {}

  function setMinter(address minter,bool active) public onlyOwner {
    isMinter[minter] = active;
  }

  function _baseURI() internal pure override returns (string memory) {
    return "ipfs://bafybeiea4u4ikyhpnx5p25wmfinfht4dvnnd5bg5qqzoefnghudtekkx6a/metadata/";
  }

  function safeMint(address to,uint256 tokenId) public {
    require(isMinter[msg.sender], "Only minter");
    _safeMint(to, tokenId);
  }

  // The following functions are overrides required by Solidity.

  function _beforeTokenTransfer(address from, address to, uint256 tokenId)
    internal
    override(ERC721, ERC721Enumerable)
  {
    super._beforeTokenTransfer(from, to, tokenId);
  }

  function supportsInterface(bytes4 interfaceId)
    public
    view
    override(ERC721, ERC721Enumerable)
    returns (bool)
  {
    return super.supportsInterface(interfaceId);
  }
}
