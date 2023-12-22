// SPDX-License-Identifier: MIT
// Based on OpenZeppelin Contracts v4.4.1 (token/ERC721/extensions/ERC721Enumerable.sol)
pragma solidity ^0.8.0;

import "./IEnumerableEscrow.sol";

error OwnerIndexOutOfBounds(uint256 index);
error GlobalIndexOutOfBounds(uint256 index);

/**
 * @title Adapted ERC-721 enumeration extension for escrow contracts
 */
abstract contract EnumerableEscrow is IEnumerableEscrow {
	// Mapping from owner to amount of tokens stored in escrow
	mapping(address => uint256) private _ownedTokenBalances;

	// Mapping from owner to list of owned token IDs
	mapping(address => mapping(uint256 => uint256)) private _ownedTokens;

	// Mapping from token ID to index of the owner tokens list
	mapping(uint256 => uint256) private _ownedTokensIndex;

	// Array with all token ids, used for enumeration
	uint256[] private _allTokens;

	// Mapping from token id to position in the allTokens array
	mapping(uint256 => uint256) private _allTokensIndex;

	/**
	 * @dev See {IEnumerableEscrow-tokenOfOwnerByIndex}.
	 */
	function balanceOf(address owner) public view returns (uint256) {
		return _ownedTokenBalances[owner];
	}

	/**
	 * @dev See {IEnumerableEscrow-tokenOfOwnerByIndex}.
	 */
	function tokenOfOwnerByIndex(address owner, uint256 index) public view returns (uint256) {
		if (index >= _ownedTokenBalances[owner]) revert OwnerIndexOutOfBounds(index);
		return _ownedTokens[owner][index];
	}

	/**
	 * @dev See {IEnumerableEscrow-totalSupply}.
	 */
	function totalSupply() public view returns (uint256) {
		return _allTokens.length;
	}

	/**
	 * @dev See {IEnumerableEscrow-tokenByIndex}.
	 */
	function tokenByIndex(uint256 index) public view returns (uint256) {
		if (index >= EnumerableEscrow.totalSupply()) revert GlobalIndexOutOfBounds(index);
		return _allTokens[index];
	}

	/**
	 * @dev Internal function to remove a token from this extension's token-and-ownership-tracking data structures.
	 * Checks whether token is part of the collection beforehand, so it can be used as part of token recovery
	 * @param owner address representing the previous owner of the given token ID
	 * @param tokenId uint256 ID of the token to be removed from the tokens list of the given address
	 */
	function _removeTokenFromEnumeration(address owner, uint256 tokenId) internal {
		_removeTokenFromAllTokensEnumeration(tokenId);
		_removeTokenFromOwnerEnumeration(owner, tokenId);
	}

	/**
	 * @dev Internal function to add a token to this extension's token-and-ownership-tracking data structures.
	 * @param owner address representing the new owner of the given token ID
	 * @param tokenId uint256 ID of the token to be added to the tokens list of the given address
	 */
	function _addTokenToEnumeration(address owner, uint256 tokenId) internal {
		_addTokenToAllTokensEnumeration(tokenId);
		_addTokenToOwnerEnumeration(owner, tokenId);
	}

	/**
	 * @dev Private function to add a token to this extension's ownership-tracking data structures.
	 * @param owner address representing the new owner of the given token ID
	 * @param tokenId uint256 ID of the token to be added to the tokens list of the given address
	 */
	function _addTokenToOwnerEnumeration(address owner, uint256 tokenId) private {
		uint256 length = _ownedTokenBalances[owner];
		_ownedTokens[owner][length] = tokenId;
		_ownedTokensIndex[tokenId] = length;
		_ownedTokenBalances[owner]++;
	}

	/**
	 * @dev Private function to add a token to this extension's token tracking data structures.
	 * @param tokenId uint256 ID of the token to be added to the tokens list
	 */
	function _addTokenToAllTokensEnumeration(uint256 tokenId) private {
		_allTokensIndex[tokenId] = _allTokens.length;
		_allTokens.push(tokenId);
	}

	/**
	 * @dev Private function to remove a token from this extension's ownership-tracking data structures. Note that
	 * while the token is not assigned a new owner, the `_ownedTokensIndex` mapping is _not_ updated: this allows for
	 * gas optimizations e.g. when performing a transfer operation (avoiding double writes).
	 * This has O(1) time complexity, but alters the order of the _ownedTokens array.
	 * @param owner address representing the previous owner of the given token ID
	 * @param tokenId uint256 ID of the token to be removed from the tokens list of the given address
	 */
	function _removeTokenFromOwnerEnumeration(address owner, uint256 tokenId) private {
		// To prevent a gap in from's tokens array, we store the last token in the index of the token to delete, and
		// then delete the last slot (swap and pop).

		uint256 lastTokenIndex = _ownedTokenBalances[owner] - 1;
		uint256 tokenIndex = _ownedTokensIndex[tokenId];

		// When the token to delete is the last token, the swap operation is unnecessary
		if (tokenIndex != lastTokenIndex) {
			uint256 lastTokenId = _ownedTokens[owner][lastTokenIndex];

			_ownedTokens[owner][tokenIndex] = lastTokenId; // Move the last token to the slot of the to-delete token
			_ownedTokensIndex[lastTokenId] = tokenIndex; // Update the moved token's index
		}

		// This also deletes the contents at the last position of the array
		delete _ownedTokensIndex[tokenId];
		delete _ownedTokens[owner][lastTokenIndex];
		_ownedTokenBalances[owner]--;
	}

	/**
	 * @dev Private function to remove a token from this extension's token tracking data structures.
	 * This has O(1) time complexity, but alters the order of the _allTokens array.
	 * @param tokenId uint256 ID of the token to be removed from the tokens list
	 */
	function _removeTokenFromAllTokensEnumeration(uint256 tokenId) private {
		// To prevent a gap in the tokens array, we store the last token in the index of the token to delete, and
		// then delete the last slot (swap and pop).

		uint256 lastTokenIndex = _allTokens.length - 1;
		uint256 tokenIndex = _allTokensIndex[tokenId];

		// When the token to delete is the last token, the swap operation is unnecessary. However, since this occurs so
		// rarely (when the last minted token is burnt) that we still do the swap here to avoid the gas cost of adding
		// an 'if' statement (like in _removeTokenFromOwnerEnumeration)
		uint256 lastTokenId = _allTokens[lastTokenIndex];

		_allTokens[tokenIndex] = lastTokenId; // Move the last token to the slot of the to-delete token
		_allTokensIndex[lastTokenId] = tokenIndex; // Update the moved token's index

		// This also deletes the contents at the last position of the array
		delete _allTokensIndex[tokenId];
		_allTokens.pop();
	}
}

