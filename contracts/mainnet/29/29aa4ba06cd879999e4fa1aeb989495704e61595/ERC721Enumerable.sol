// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Pixel.sol";
import "./IERC721Enumerable.sol";

/**
 * @dev This implements an optional extension of {ERC721} defined in the EIP that adds
 * enumerability of all the token ids in the contract as well as all token ids owned by each
 * account.
 */
abstract contract ERC721Enumerable is Pixel, IERC721Enumerable {
  /**
   * @dev See {IERC165-supportsInterface}.
   */
  function supportsInterface(bytes4 interfaceId) public view virtual override(IERC165, Pixel) returns (bool) {
    return interfaceId == type(IERC721Enumerable).interfaceId || super.supportsInterface(interfaceId);
  }

  /**
   * @dev See {IERC721Enumerable-tokenOfOwnerByIndex}.
   */
  function tokenOfOwnerByIndex(address owner, uint256 index) public view virtual override returns (uint256) {
    require(index < balanceOf(owner), "ERC721Enumerable: owner index out of bounds");
    uint16 count = 0;
    for (uint16 i = 1; i < 1025; i++) {
      if (ownerOf(i) == owner) {
        count++;
        if (index == count - 1) {
          return i;
        }
      }
    }
    require(false, "There is no Id with this owner/index pair");
  }

  /**
   * @dev See {IERC721Enumerable-totalSupply}.
   */
  function totalSupply() public view virtual override returns (uint256) {
    return 1024;
  }

  /**
   * @dev See {IERC721Enumerable-tokenByIndex}.
   */
  function tokenByIndex(uint256 index) public view virtual override returns (uint256) {
    require(index < 1024, "index can be from 0 to 1023");
    return index + 1;
  }
}

