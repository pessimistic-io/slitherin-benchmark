// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "./ERC721Enumerable.sol";
import "./Math.sol";
import "./Strings.sol";
import "./Counters.sol";
import "./MinterControl.sol";

contract SmolBodiesPets is MinterControl, ERC721Enumerable {
    using Strings for uint256;
    using Counters for Counters.Counter;

    Counters.Counter private _tokenIdTracker;

    string public baseURI;

    event BaseURIChanged(string from, string to);
    event SmolPetMint(address indexed to, uint256 tokenId, string tokenURI);

    constructor() ERC721("Smol Bodies Pets", "BODYPETS") {
        _tokenIdTracker.increment(); // Start id at 1 instead of 0
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721Enumerable, AccessControl)
        returns (bool)
    {
        return
            ERC721Enumerable.supportsInterface(interfaceId) ||
            AccessControl.supportsInterface(interfaceId);
    }

    function mint(address _to) external onlyMinter {
        uint256 _tokenId = _tokenIdTracker.current();

        _safeMint(_to, _tokenId);
        _tokenIdTracker.increment();

        emit SmolPetMint(_to, _tokenId, tokenURI(_tokenId));
    }

    function tokenURI(uint256 _tokenId)
        public
        view
        override
        returns (string memory)
    {
        require(_exists(_tokenId), "Smol Bodies Pets: URI query for nonexistent token");

        return
            bytes(baseURI).length > 0
                ? string(abi.encodePacked(baseURI, _tokenId.toString(), ".json"))
                : "";
    }

    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }

    // ADMIN

    function setBaseURI(string memory _baseURItoSet) external onlyOwner {
        emit BaseURIChanged(baseURI, _baseURItoSet);

        baseURI = _baseURItoSet;
    }
}

