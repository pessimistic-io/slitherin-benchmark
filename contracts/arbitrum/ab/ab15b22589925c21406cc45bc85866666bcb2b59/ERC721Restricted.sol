// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity 0.8.15;

import {PausableAuth, Authority, Auth} from "./PausableAuth.sol";

import {ERC721} from "./ERC721.sol";
import {Counters} from "./Counters.sol";
import {Strings} from "./Strings.sol";

/// @notice ERC721 with restricted transfers.
/// @author Dinari (https://github.com/dinaricrypto/dinari-contracts/blob/main/contracts/tokens/NonTransferableToken.sol)
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC721/extensions/ERC721Enumerable.sol)
contract ERC721Restricted is ERC721, PausableAuth {
    using Counters for Counters.Counter;
    using Strings for uint256;

    error ERC721Restricted__NotOwner(address account);

    /// @dev Agreement ID generator
    Counters.Counter private _ids;

    string public baseURI;

    // solhint-disable-next-line no-empty-blocks
    constructor(
        string memory _name,
        string memory _symbol,
        address _owner,
        Authority _authority
    ) ERC721(_name, _symbol) Auth(_owner, _authority) {
        _pause();
    }

    function setName(string calldata newName) external requiresAuth {
        name = newName;
    }

    function setSymbol(string calldata newSymbol) external requiresAuth {
        symbol = newSymbol;
    }

    function setBaseURI(string calldata newBaseURI) external requiresAuth {
        baseURI = newBaseURI;
    }

    function mint(address to) public virtual returns (uint256) {
        if (msg.sender != owner) revert ERC721Restricted__NotOwner(msg.sender);

        uint256 newId = _ids.current();
        _ids.increment();
        _beforeTokenTransfer(address(0), to, newId);
        _mint(to, newId);
        _afterTokenTransfer(address(0), to, newId);
        return newId;
    }

    function burn(uint256 tokenId) public virtual {
        if (msg.sender != owner) revert ERC721Restricted__NotOwner(msg.sender);

        address tokenOwner = _ownerOf[tokenId];
        _beforeTokenTransfer(tokenOwner, address(0), tokenId);
        _burn(tokenId);
        _afterTokenTransfer(tokenOwner, address(0), tokenId);
    }

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        return string.concat(baseURI, tokenId.toString());
    }

    function transferFrom(
        address from,
        address to,
        uint256 id
    ) public virtual override {
        _beforeTokenTransfer(from, to, id);
        super.transferFrom(from, to, id);
        _afterTokenTransfer(from, to, id);
    }

    /*//////////////////////////////////////////////////////////////
                            ERC721Enumerable
    //////////////////////////////////////////////////////////////*/

    // Mapping from owner to list of owned token IDs
    mapping(address => mapping(uint256 => uint256)) public tokenOfOwnerByIndex;

    // Mapping from token ID to index of the owner tokens list
    mapping(uint256 => uint256) private _ownedTokensIndex;

    // Array with all token ids, used for enumeration
    uint256[] public tokenByIndex;

    // Mapping from token id to position in the allTokens array
    mapping(uint256 => uint256) private _allTokensIndex;

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return
            interfaceId == 0x780e9d63 || // ERC165 Interface ID for ERC721Enumerable
            super.supportsInterface(interfaceId);
    }

    /**
     * @dev See {IERC721Enumerable-totalSupply}.
     */
    function totalSupply() public view virtual returns (uint256) {
        return tokenByIndex.length;
    }

    /**
     * @dev Hook that is called before any token transfer. This includes minting
     * and burning.
     *
     * Calling conditions:
     *
     * - When `from` and `to` are both non-zero, ``from``'s `tokenId` will be
     * transferred to `to`.
     * - When `from` is zero, `tokenId` will be minted for `to`.
     * - When `to` is zero, ``from``'s `tokenId` will be burned.
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     *
     * To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal virtual onlyAuthorizedWhenPaused {
        if (from == address(0)) {
            _addTokenToAllTokensEnumeration(tokenId);
        } else if (from != to) {
            _removeTokenFromOwnerEnumeration(from, tokenId);
        }
        if (to == address(0)) {
            _removeTokenFromAllTokensEnumeration(tokenId);
        } else if (to != from) {
            _addTokenToOwnerEnumeration(to, tokenId);
        }
    }

    function _afterTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal virtual {}

    /**
     * @dev Private function to add a token to this extension's ownership-tracking data structures.
     * @param to address representing the new owner of the given token ID
     * @param tokenId uint256 ID of the token to be added to the tokens list of the given address
     */
    function _addTokenToOwnerEnumeration(address to, uint256 tokenId) private {
        uint256 length = ERC721.balanceOf(to);
        tokenOfOwnerByIndex[to][length] = tokenId;
        _ownedTokensIndex[tokenId] = length;
    }

    /**
     * @dev Private function to add a token to this extension's token tracking data structures.
     * @param tokenId uint256 ID of the token to be added to the tokens list
     */
    function _addTokenToAllTokensEnumeration(uint256 tokenId) private {
        _allTokensIndex[tokenId] = tokenByIndex.length;
        tokenByIndex.push(tokenId);
    }

    /**
     * @dev Private function to remove a token from this extension's ownership-tracking data structures. Note that
     * while the token is not assigned a new owner, the `_ownedTokensIndex` mapping is _not_ updated: this allows for
     * gas optimizations e.g. when performing a transfer operation (avoiding double writes).
     * This has O(1) time complexity, but alters the order of the tokenOfOwnerByIndex array.
     * @param from address representing the previous owner of the given token ID
     * @param tokenId uint256 ID of the token to be removed from the tokens list of the given address
     */
    function _removeTokenFromOwnerEnumeration(address from, uint256 tokenId) private {
        // To prevent a gap in from's tokens array, we store the last token in the index of the token to delete, and
        // then delete the last slot (swap and pop).

        uint256 lastTokenIndex = ERC721.balanceOf(from) - 1;
        uint256 tokenIndex = _ownedTokensIndex[tokenId];

        // When the token to delete is the last token, the swap operation is unnecessary
        if (tokenIndex != lastTokenIndex) {
            uint256 lastTokenId = tokenOfOwnerByIndex[from][lastTokenIndex];

            tokenOfOwnerByIndex[from][tokenIndex] = lastTokenId; // Move the last token to the slot of the to-delete token
            _ownedTokensIndex[lastTokenId] = tokenIndex; // Update the moved token's index
        }

        // This also deletes the contents at the last position of the array
        delete _ownedTokensIndex[tokenId];
        delete tokenOfOwnerByIndex[from][lastTokenIndex];
    }

    /**
     * @dev Private function to remove a token from this extension's token tracking data structures.
     * This has O(1) time complexity, but alters the order of the tokenByIndex array.
     * @param tokenId uint256 ID of the token to be removed from the tokens list
     */
    function _removeTokenFromAllTokensEnumeration(uint256 tokenId) private {
        // To prevent a gap in the tokens array, we store the last token in the index of the token to delete, and
        // then delete the last slot (swap and pop).

        uint256 lastTokenIndex = tokenByIndex.length - 1;
        uint256 tokenIndex = _allTokensIndex[tokenId];

        // When the token to delete is the last token, the swap operation is unnecessary. However, since this occurs so
        // rarely (when the last minted token is burnt) that we still do the swap here to avoid the gas cost of adding
        // an 'if' statement (like in _removeTokenFromOwnerEnumeration)
        uint256 lastTokenId = tokenByIndex[lastTokenIndex];

        tokenByIndex[tokenIndex] = lastTokenId; // Move the last token to the slot of the to-delete token
        _allTokensIndex[lastTokenId] = tokenIndex; // Update the moved token's index

        // This also deletes the contents at the last position of the array
        delete _allTokensIndex[tokenId];
        tokenByIndex.pop();
    }
}

