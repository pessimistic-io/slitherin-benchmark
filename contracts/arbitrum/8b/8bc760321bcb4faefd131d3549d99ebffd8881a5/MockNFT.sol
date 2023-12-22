// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./ERC721Upgradeable.sol";
import "./OwnableUpgradeable.sol";

contract MockNFT is OwnableUpgradeable, ERC721Upgradeable {
    string _baseUri;
    string public contractURI;

    function __MockNFT__init() external initializer() {
        __Ownable_init();
        __ERC721_init_unchained("test ERC721", "t721");
    }

    function batchMint(address to, uint startTokenId, uint endTokenId) external onlyOwner {
        for (; startTokenId <= endTokenId; ++startTokenId) {
            _safeMint(to, startTokenId);
        }
    }

    function setContractURI(string memory contractURI_) external onlyOwner {
        contractURI = contractURI_;
    }

    function _baseURI() internal view override returns (string memory) {
        return _baseUri;
    }

    function setBaseURI(string memory newBaseURI) external onlyOwner {
        _baseUri = newBaseURI;
    }
}

