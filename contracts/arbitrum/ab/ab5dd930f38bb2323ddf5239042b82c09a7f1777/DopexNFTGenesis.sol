// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "./ERC721.sol";
import "./ERC721Enumerable.sol";
import "./Ownable.sol";
import "./Counters.sol";

contract DopexNFTGenesis is ERC721, ERC721Enumerable, Ownable {
    using Counters for Counters.Counter;
    using Strings for uint256;

    Counters.Counter private _tokenIdCounter;

    uint256 public MAX_SUPPLY = 32;
    string public baseURI;
    string public baseExtension = ".json";
    uint256[] public mintIDremaining;
    bool changeBaseURI = true;

    constructor() ERC721("Dopex Genesis NFT", "DopexNFTGen") {
      for (uint256 i = 0; i < MAX_SUPPLY; i++) {
        mintIDremaining.push(i+1);
        }
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

    function ownerMint() public onlyOwner {
      for (uint256 i = 0; i < MAX_SUPPLY; i++) {
        _safeMint(msg.sender, i+1);
        _tokenIdCounter.increment();
        }
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

    function withdraw() public onlyOwner {
        require(address(this).balance > 0);
        payable(owner()).transfer(address(this).balance);
    }

    // The following functions are overrides required by Solidity.
    function _beforeTokenTransfer(address from, address to, uint256 tokenId) internal override(ERC721, ERC721Enumerable) {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721, ERC721Enumerable) returns (bool){
        return super.supportsInterface(interfaceId);
    }
}
