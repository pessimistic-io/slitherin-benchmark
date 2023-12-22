// contracts/MagicAxe.sol
// SPDX-License-Identifier: MIT
// Author: evergem.xyz

pragma solidity ^0.8.17;

import "./ERC721Burnable.sol";
import "./ERC721Enumerable.sol";
import "./Counters.sol";
import "./Ownable.sol";

import "./Pausable.sol";

contract MagicAxe is ERC721Enumerable, ERC721Burnable, Ownable, Pausable {
    using Strings for uint256;
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds = Counters.Counter(500);

    // Optional mapping for token URIs
    mapping(uint256 => string) private tokenURIs;

    // Base URI
    string private baseURI;
    string private baseExt;

    constructor(
        string memory name,
        string memory symbol,
        string memory _baseURI,
        string memory _baseExt
    ) ERC721(name, symbol) {
        baseURI = _baseURI;
        baseExt = _baseExt;
    }

    function setBaseURI(string memory _newBaseURI) external onlyOwner {
        baseURI = _newBaseURI;
    }

    function setBaseExt(string memory _newBaseExt) external onlyOwner {
        baseExt = _newBaseExt;
    }

    /**
     * @dev See {IERC721Metadata-tokenURI}.
     */
    function tokenURI(uint256 tokenId)
        public
        view
        virtual
        override
        returns (string memory)
    {
        require(
            _exists(tokenId),
            "ERC721URIStorage: URI query for nonexistent token"
        );

        string memory _tokenURI = tokenURIs[tokenId];
        if (bytes(_tokenURI).length > 0) {
            return string(_tokenURI);
        }

        return
            bytes(baseURI).length > 0
                ? string(abi.encodePacked(baseURI, tokenId.toString(), baseExt))
                : "";
    }

    function setTokenURI(uint256 tokenId, string memory _tokenURI)
        external
        virtual
        onlyOwner
    {
        require(_exists(tokenId), "URI set of nonexistent token");
        tokenURIs[tokenId] = _tokenURI;
    }

    /**
     * @dev Pause
     */

    function pause() external virtual onlyOwner {
        super._pause();
    }

    /**
     * @dev Unpause
     */
    function unpause() external virtual onlyOwner {
        super._unpause();
    }

    function mint() external whenNotPaused onlyOwner returns (uint256) {
        _tokenIds.increment();
        uint256 newNftTokenId = _tokenIds.current();
        _safeMint(_msgSender(), newNftTokenId);
        return newNftTokenId;
    }

    function mintMany(address to, uint256 num)
        external
        onlyOwner
        returns (uint256[] memory)
    {
        uint256[] memory listTokenId = new uint256[](num);
        for (uint256 i = 0; i < num; i++) {
            _tokenIds.increment();
            uint256 newNftTokenId = _tokenIds.current();
            _safeMint(to, newNftTokenId);
            listTokenId[i] = newNftTokenId;
        }
        return listTokenId;
    }

    // Override
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId,
        uint256 batchSize
    ) internal override(ERC721, ERC721Enumerable) {
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC721, ERC721Enumerable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}

