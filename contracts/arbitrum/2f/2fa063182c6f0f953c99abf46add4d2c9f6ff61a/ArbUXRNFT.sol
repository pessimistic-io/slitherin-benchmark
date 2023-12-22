//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "./Ownable.sol";
import "./ERC721Enumerable.sol";

contract ArbUXRNFT is ERC721Enumerable, Ownable {
    string[] private _tokenURIs;
    mapping(uint256 => uint) private _tokenIdToTokenURIIndex;

    constructor() ERC721("ArbUXRNFT", "ARBUXR") {
    }

    function batchMint(address[] memory to, string memory _tokenURI) external onlyOwner {
        _tokenURIs.push(_tokenURI);

        for (uint i = 0; i < to.length; i++) {
            uint256 tokenId = totalSupply();
            _safeMint(to[i], tokenId);
            _tokenIdToTokenURIIndex[tokenId] = _tokenURIs.length - 1;
        }
    }

    function tokenURI(uint256 tokenId) public view override(ERC721) returns (string memory) {
        require(_exists(tokenId), "ERC721Metadata: URI query for nonexistent token");

        return _tokenURIs[_tokenIdToTokenURIIndex[tokenId]];
    }
}

