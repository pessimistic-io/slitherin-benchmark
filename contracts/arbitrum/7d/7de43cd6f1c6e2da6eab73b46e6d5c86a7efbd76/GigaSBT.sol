// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./ERC721Upgradeable.sol";
import "./ERC721URIStorageUpgradeable.sol";
import "./ERC721BurnableUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./draft-EIP712Upgradeable.sol";
import "./draft-ERC721VotesUpgradeable.sol";
import "./Initializable.sol";
import "./CountersUpgradeable.sol";

contract GigaSBT is Initializable, ERC721Upgradeable, ERC721URIStorageUpgradeable, ERC721BurnableUpgradeable, OwnableUpgradeable, EIP712Upgradeable, ERC721VotesUpgradeable {
    using CountersUpgradeable for CountersUpgradeable.Counter;

    CountersUpgradeable.Counter private _tokenIdCounter;

    string internal _baseTokenURI;

    event BaseTokenURI(string uri);

    function initialize(string memory uri) initializer public {
        __ERC721_init("GigaSpace Achievements", "GSBT");
        __ERC721URIStorage_init();
        __ERC721Burnable_init();
        __Ownable_init();
        __EIP712_init("GigaSpace Achievements", "1");
        __ERC721Votes_init();

        _baseTokenURI = uri;
    }

    function safeMint(address to, string memory uri) public onlyOwner {
        uint256 tokenId = _tokenIdCounter.current();
        _tokenIdCounter.increment();
        _safeMint(to, tokenId);
        _setTokenURI(tokenId, uri);
    }

    // The following functions are overrides required by Solidity.

    function _beforeTokenTransfer(address from, address to, uint256 tokenId, uint256 batchSize)
        internal
        override(ERC721Upgradeable)
        {
            require(from == address(0)  && to != address(0), "Err: token is SOUL BOUND");
            super._beforeTokenTransfer(from, to, tokenId, batchSize);
        }

    function _afterTokenTransfer(address from, address to, uint256 tokenId, uint256 batchSize)
        internal
        override(ERC721Upgradeable, ERC721VotesUpgradeable)
    {
        super._afterTokenTransfer(from, to, tokenId, batchSize);
    }

    function _burn(uint256 tokenId)
        internal
        override(ERC721Upgradeable, ERC721URIStorageUpgradeable)
    {
        super._burn(tokenId);
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721Upgradeable, ERC721URIStorageUpgradeable)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }

    /// @notice Set IPFS base URI
    function setBaseTokenURI(string memory uri) external onlyOwner {
        _baseTokenURI = uri;
        emit BaseTokenURI(uri);
    }

}
