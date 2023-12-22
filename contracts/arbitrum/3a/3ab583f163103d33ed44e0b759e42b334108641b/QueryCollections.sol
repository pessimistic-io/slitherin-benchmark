// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "./extensions_IERC721Enumerable.sol";
import "./extensions_IERC721Metadata.sol";
import "./ERC721Enumerable.sol";
import "./ERC165Checker.sol";

interface ICompleteERC721 is IERC721Enumerable, IERC721Metadata {}

contract QueryCollections {
    using ERC165Checker for address;

    modifier onlySupported(address _collection) {
        bool isEnumerable = _collection.supportsInterface(
            type(IERC721Enumerable).interfaceId
        );
        bool hasMetadata = _collection.supportsInterface(
            type(IERC721Metadata).interfaceId
        );

        require(isEnumerable && hasMetadata, "NFT not supported");
        _;
    }

    function getOwners(
        address _collection,
        uint256 _start,
        uint256 _stop
    ) public view onlySupported(_collection) returns (address[] memory owners) {
        require(_start <= _stop, "Start cannot be greater than stop");
        ICompleteERC721 collection = ICompleteERC721(_collection);
        uint256 totalSupply = collection.totalSupply();

        if (_stop > totalSupply) {
            _stop = totalSupply;
        }
        address[] memory _owners = new address[](_stop - _start);
        for (uint256 i = 0; i < _stop - _start; i++) {
            _owners[i] = collection.ownerOf(i + _start);
        }
        return _owners;
    }

    function getGeneralInfo(address _collection)
        public
        view
        onlySupported(_collection)
        returns (
            string memory name,
            string memory symbol,
            uint256 totalSupply
        )
    {
        ICompleteERC721 collection = ICompleteERC721(_collection);
        name = collection.name();
        symbol = collection.symbol();
        totalSupply = collection.totalSupply();
        return (name, symbol, totalSupply);
    }

    function getMetadata(
        address _collection,
        uint256 _start,
        uint256 _stop
    )
        public
        view
        onlySupported(_collection)
        returns (string[] memory metadata)
    {
        require(_start <= _stop, "Start cannot be greater than stop");
        ICompleteERC721 collection = ICompleteERC721(_collection);
        uint256 totalSupply = collection.totalSupply();
        if (_stop > totalSupply) {
            _stop = totalSupply;
        }
        string[] memory _metadata = new string[](_stop - _start);
        for (uint256 i = 0; i < _stop - _start; i++) {
            _metadata[i] = collection.tokenURI(i + _start);
        }
        return _metadata;
    }
}

