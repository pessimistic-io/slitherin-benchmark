// SPDX-License-Identifier: MIT
pragma solidity ^0.8.1;

import "./ERC721.sol";
import "./ERC721URIStorage.sol";
import "./Ownable.sol";

// @author: https://www.neuralmetrics.ai

contract NMAwardsNFT is ERC721, ERC721URIStorage, Ownable {
    uint256 private _tokenCounter;
    string private _contractURI;

    constructor(string memory contractURI) ERC721("NeuralMetrics Awards", "NMAWARDS") {
        _tokenCounter = 0;
        _contractURI = contractURI;
    }

    function mint(address recipient, string memory _tokenURI) public onlyOwner {
        _safeMint(recipient, _tokenCounter);
        _setTokenURI(_tokenCounter, _tokenURI);
        _tokenCounter++;
    }

    function updateContractURI(string memory contractURI) public onlyOwner {
        _contractURI = contractURI;
    }

    // Override the required functions from ERC721
    function _burn(uint256 tokenId) internal override(ERC721, ERC721URIStorage) {
        super._burn(tokenId);
    }

    function tokenURI(uint256 tokenId) public view override(ERC721, ERC721URIStorage) returns (string memory) {
        return ERC721URIStorage.tokenURI(tokenId);
    }
}
