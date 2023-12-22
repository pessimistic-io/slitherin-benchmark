// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "./ERC721.sol";
import "./ERC721Enumerable.sol";
import "./Ownable.sol";
import "./Counters.sol";

contract DopexMithicalNFT is ERC721, ERC721Enumerable, Ownable {
    using Counters for Counters.Counter;
    using Strings for uint256;

    string public baseURI;
    bool changeBaseURI = true;

    constructor() ERC721("Dopex Mithical NFT", "DopexMithicalNFT") {
      _safeMint(msg.sender, 1);
    }

    function disableChangeBaseURI() public onlyOwner {
        changeBaseURI = false;
    }

    function setBaseURI(string memory _newBaseURI) public onlyOwner {
        require(changeBaseURI);
        baseURI = _newBaseURI;
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return baseURI;
    }

    function tokenURI(uint256 _tokenURI) public view virtual override returns (string memory){
        require(_exists(_tokenURI),"ERC721Metadata: URI query for nonexistent token");

        string memory base = _baseURI();

        // If there is no base URI, return the token URI.
        if (bytes(base).length == 0) {
            return _tokenURI.toString();
        }

        return string(abi.encodePacked(base, "/", _tokenURI.toString()));
    }

    // The following functions are overrides required by Solidity.
    function _beforeTokenTransfer(address from, address to, uint256 tokenId) internal override(ERC721, ERC721Enumerable) {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721, ERC721Enumerable) returns (bool){
        return super.supportsInterface(interfaceId);
    }
}
