// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {ERC721} from "./ERC721.sol";

abstract contract ERC721Queryable is ERC721 {
    error OwnerIndexOutOfBounds();
    error OwnerIndexNotExist();

    uint256 private _mintedAmount;
    uint256 private immutable _collectionSize;

    /**
     * @notice Constructor
     * @param size_ the collection size
     */
    constructor(uint256 size_) {
        _collectionSize = size_;
    }

    /**
     * @notice Returns the total amount of tokens stored by the contract
     */
    function totalSupply() public view returns (uint256) {
        return _mintedAmount;
    }

    /**
     * @notice Returns a token ID owned by `owner` at a given `index` of its token list.
     * @dev This read function is O(totalSupply). If calling from a separate contract, be sure to test gas first.
     * It may also degrade with extremely large collection sizes (e.g >> 10000), test for your use case.
     * @param owner token owner
     * @param index index of its token list
     */
    function tokenOfOwnerByIndex(address owner, uint256 index) public view returns (uint256) {
        if (index >= balanceOf(owner)) {
            revert OwnerIndexOutOfBounds();
        }

        uint256 currentIndex = 0;
        unchecked {
            for (uint256 tokenId = 0; tokenId < _collectionSize; tokenId++) {
                if (_exists(tokenId) && owner == ownerOf(tokenId)) {
                    if (currentIndex == index) {
                        return tokenId;
                    }
                    currentIndex++;
                }
            }
        }

        // Execution should never reach this point.
        revert OwnerIndexNotExist();
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 firstTokenId,
        uint256 batchSize
    ) internal virtual override {
        super._beforeTokenTransfer(from, to, firstTokenId, batchSize);

        if (from == address(0)) {
            _mintedAmount += 1;
        }
        if (to == address(0)) {
            _mintedAmount -= 1;
        }
    }
}

