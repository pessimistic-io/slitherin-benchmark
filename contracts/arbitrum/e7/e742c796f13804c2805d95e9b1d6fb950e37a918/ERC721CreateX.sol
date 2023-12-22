// SPDX-License-Identifier: MIT
// Creator: Chiru Labs

pragma solidity ^0.8.0;

import "./IERC721.sol";
import "./IERC721Receiver.sol";
import "./IERC721Metadata.sol";
import "./IERC721Enumerable.sol";
import "./Address.sol";
import "./Context.sol";
import "./Strings.sol";
import "./ERC165.sol";
import "./ERC721.sol";
import "./ERC721Enumerable.sol";

contract ERC721CreateX is Context, ERC165, ERC721, ERC721Enumerable {
    // Token name
    string internal _name;

    // Token symbol
    string internal _symbol;

    constructor(
        string memory name_,
        string memory symbol_
    ) ERC721(name_, symbol_) {
        _name = name_;
        _symbol = symbol_;
    }

    using Strings for uint256;

    function safeMint(address to, uint256 tokenId) internal {
        _safeMint(to, tokenId);
    }

    // The following functions are overrides required by Solidity.

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId,
        uint256 batchSize
    ) internal override(ERC721, ERC721Enumerable) {
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
    }

    function supportsInterface(
        bytes4 interfaceId
    )
        public
        view
        virtual
        override(ERC165, ERC721, ERC721Enumerable)
        returns (bool)
    {
        return
            interfaceId == type(ERC721Enumerable).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    /**
     * @dev return the collection Base MetaData URI
     */
    function getCollectionURI() public view virtual returns (string memory) {
        string memory collectionURI_ = _collectionBaseURI();
        if (bytes(collectionURI_).length > 0) {
            return collectionURI_;
        } else {
            return _baseURI();
        }
    }

    /**
     * @dev collection Base URI for computing {collectionURI}. If set, the resulting URI for collection Level return.
     * Empty by default, can be overriden in child contracts.
     */
    function _collectionBaseURI()
        internal
        view
        virtual
        returns (string memory)
    {
        return "";
    }

    /**
     * @dev See {IERC721Metadata-tokenURI}.
     * Support LazyMint, to be query by standard way
     */
    function tokenURI(
        uint256 tokenId
    ) public view virtual override returns (string memory) {
        string memory baseURI = _baseURI();
        return
            bytes(baseURI).length > 0
                ? string(abi.encodePacked(baseURI, tokenId.toString()))
                : "";
    }

    /**
     * @dev Returns whether `tokenId` exists.
     * Tokens start existing when they are minted (`_mint`),
     *
     * Can be Use to detect the TokenId is exist or not.
        If not exist, can be consider a lazy mint(If it should/can be minted, but not be minted yet)
     */
    function exists(uint256 tokenId) public view returns (bool) {
        return _exists(tokenId);
    }

    function name() public view virtual override returns (string memory) {
        return _name;
    }

    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }
}

