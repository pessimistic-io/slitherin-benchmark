// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./ERC721.sol";
import "./ERC721Enumerable.sol";
import "./Counters.sol";
import "./Ownable.sol";

contract Adventure000 is ERC721Enumerable, Ownable {
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIdTracker;
    string private uri;

    constructor(
        string memory _name,
        string memory _symbol,
        string memory _tokenURI
    ) ERC721(_name, _symbol) {
        uri = _tokenURI;
    }

    function setTokenURI(string calldata _tokenURI) external onlyOwner {
        uri = _tokenURI;
    }

    function drop(address[] calldata to) external onlyOwner {
        uint256 currentId = _tokenIdTracker.current();
        unchecked {
            for (uint256 i = 0; i < to.length; i++) {
                _safeMint(to[i], ++currentId);
                _tokenIdTracker.increment();
            }
        }
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override
        returns (string memory)
    {
        require(
            _exists(tokenId),
            "ERC721Metadata: URI query for nonexistent token"
        );
        return uri;
    }
}

