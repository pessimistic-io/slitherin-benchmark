// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./ERC721Upgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./Initializable.sol";

contract NFTGenerator is ERC721Upgradeable, OwnableUpgradeable {
    bool private initialized;
    uint256 private tokenIdCounter;
    mapping(uint256 => string) private tokenURIs;

    function initialize(address owner) public initializer {
        __ERC721_init("GreenWebMeterNFT", "GWEBMETNFT");

        // set the owner of the contract
        _transferOwnership(owner);

        __Ownable_init();
        tokenIdCounter = 0;
    }

    function generateNFT(string memory metadataUrl) public onlyOwner {
        require(bytes(metadataUrl).length > 0, "Metadata URL cannot be empty");

        uint256 tokenId = tokenIdCounter;
        tokenIdCounter++;

        _safeMint(msg.sender, tokenId);


        tokenURIs[tokenId] = metadataUrl;
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_exists(tokenId), "Token does not exist");

        return tokenURIs[tokenId];
    }

    // function that allows only the owner to see the total number of NFTs generated
    function totalNFTs() public view onlyOwner returns (uint256) {
        return tokenIdCounter;
    }
}


