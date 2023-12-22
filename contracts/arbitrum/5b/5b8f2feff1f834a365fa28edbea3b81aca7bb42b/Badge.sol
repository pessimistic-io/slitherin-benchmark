// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "./ERC721EnumerableUpgradeable.sol";
import "./OwnableUpgradeable.sol";

contract Badge is OwnableUpgradeable, ERC721EnumerableUpgradeable {
    string private _baseUri;
    string public contractURI;

    function __Badge_init(
        string memory name,
        string memory symbol
    ) external initializer() {
        __Ownable_init_unchained();
        __ERC721_init(name, symbol);
    }

    function _baseURI() internal view override returns (string memory) {
        return _baseUri;
    }

    function setBaseURI(string memory newBaseURI) external onlyOwner {
        _baseUri = newBaseURI;
    }

    function setContractURI(string memory newContractURI) external onlyOwner {
        contractURI = newContractURI;
    }

    function batchMint(uint[] calldata tokenIds, address[] calldata recipients) external onlyOwner {
        uint len = tokenIds.length;
        require(len == recipients.length, "unmatched length");
        for (uint i = 0; i < len; ++i) {
            _safeMint(recipients[i], tokenIds[i]);
        }
    }

    uint[48] private __gap;
}

