// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./StructuredLinkedList.sol";
import "./ERC721.sol";
import "./ERC721Burnable.sol";
import "./IERC4906.sol";
import "./Ownable.sol";
import "./Counters.sol";

contract CryptoplazaMember is ERC721, IERC4906, ERC721Burnable, Ownable {
    using Counters for Counters.Counter;
    using StructuredLinkedList for StructuredLinkedList.List;

    Counters.Counter private _tokenIdCounter;

    string public baseURI;

    //tokenId => timestamp
    mapping(uint256 => uint256) public tokenTenure;
    StructuredLinkedList.List tokenIdSortedByTenure;

    constructor(
        string memory _name,
        string memory _symbol,
        string memory _baseUri
    ) ERC721(_name, _symbol) {
        baseURI = _baseUri;
        //To avoid the first nft to be 0
        _tokenIdCounter.increment();
    }

    function safeMint(address to, uint256 tenure) public onlyOwner {
        uint256 tokenId = _tokenIdCounter.current();
        _tokenIdCounter.increment();
        _safeMint(to, tokenId);
        tokenTenure[tokenId] = tenure;
        _addTokenIdSortedByTenure(tokenId, tenure);
        emit BatchMetadataUpdate(1, tokenId);
    }

    function getTenure(uint256 tokenId) internal view returns (uint8) {
        uint256 duration = block.timestamp - tokenTenure[tokenId];

        uint256 durationYears = duration / 31536000; // 1 year = 31536000 s

        if (durationYears < 3) {
            return 1;
        } else if (durationYears < 5) {
            return 2;
        } else {
            return 3;
        }
    }


    function _addTokenIdSortedByTenure(
        uint256 tokenId,
        uint256 tenure
    ) internal {
        if (tokenIdSortedByTenure.sizeOf() == 0) {
            tokenIdSortedByTenure.insertAfter(0, tokenId);
        } else {
            (, uint256 next) = tokenIdSortedByTenure.getNextNode(0);
            while ((next != 0) && (tenure > tokenTenure[next])) {
                (, next) = tokenIdSortedByTenure.getNextNode(next);
            }
            tokenIdSortedByTenure.insertBefore(next, tokenId);
        }
    }

    function _indexOfToken(uint256 tokenId) internal view returns (uint256) {
        uint256 index = 1;
        (, uint256 next) = tokenIdSortedByTenure.getNextNode(0);
        while ((next != 0) && ((next != tokenId))) {
            (, next) = tokenIdSortedByTenure.getNextNode(next);
            index += 1;
        }
        return index;
    }

    // The following functions are overrides

    function tokenURI(
        uint256 tokenId
    ) public view override(ERC721) returns (string memory) {
        _requireMinted(tokenId);

        uint8 tenure = getTenure(tokenId);
        uint256 index = _indexOfToken(tokenId);

        return
            bytes(baseURI).length > 0
                ? string(
                    abi.encodePacked(
                        baseURI,
                        Strings.toString(tenure),
                        "/",
                        Strings.toString(index)
                    )
                )
                : "";
    }

    function _burn(uint256 tokenId) internal override(ERC721) {
        require(tokenTenure[tokenId] != 0, "TokenId not exist");
        delete tokenTenure[tokenId];
        tokenIdSortedByTenure.remove(tokenId);
        super._burn(tokenId);
    }

    function burn(uint256 tokenId) public override(ERC721Burnable) {
        require(
            _isApprovedOrOwner(_msgSender(), tokenId) ||
                owner() == _msgSender(),
            "CryptoplazaNFT: caller is not token owner or approved"
        );
        _burn(tokenId);

    }

    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }
}

