// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "./ERC721.sol";
import "./ERC721URIStorage.sol";
import "./Counters.sol";


contract NFTWarTrophy is ERC721, ERC721URIStorage {
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;
    mapping(string => uint8) hashes;

    constructor() ERC721("NFTWarTrophy", "NWT") {}

    function _burn(uint256 tokenId) 
        internal 
        override(ERC721, ERC721URIStorage) 
    {
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


    function awardItem(address recipient, string memory hash, string memory metadata) 
        public
        returns (uint256)
    {
        require(hashes[hash] != 1, "Already minted");
        hashes[hash] = 1;
        _tokenIds.increment();
        uint256 newItemId = _tokenIds.current();
        _mint(recipient, newItemId);
        _setTokenURI(newItemId, metadata);
        return newItemId;
    }
}

