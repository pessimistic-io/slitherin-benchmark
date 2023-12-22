//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "./ERC721URIStorage.sol";

import "./ERC721Enumerable.sol";
import "./Counters.sol";


contract ArbNFT is ERC721URIStorage, ERC721Enumerable {
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;

    constructor(string memory name, string memory symbol) ERC721(name,symbol) public {
    }


    function mint(address to, string memory uri) internal {
        _tokenIds.increment();
        uint256 newTokenId = _tokenIds.current();
        _mint(to, newTokenId);
        _setTokenURI(newTokenId, uri);
    }

    function _batchMint(address[] memory tos, string[] memory uris) internal {
        require(tos.length == uris.length, "INVALID_INPUT_LENTHS");
        for ( uint i = 0; i < tos.length; i++) {
            mint(tos[i], uris[i]);
        }
    }

    function _beforeTokenTransfer(address from, address to, uint256 tokenId)
        internal
        override(ERC721, ERC721Enumerable)
    {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    function _burn(uint256 tokenId) internal override(ERC721, ERC721URIStorage) {
        super._burn(tokenId);
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721, ERC721URIStorage)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override( ERC721, ERC721Enumerable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }


}
