// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./IERC721Enumerable.sol";

contract ERC721BulkTransfer {
    function bulkTransferAll(IERC721Enumerable tokenContract, address recipient) external {
        uint256 balance = tokenContract.balanceOf(msg.sender);
        for (uint256 index; index < balance; index++) {
            tokenContract.transferFrom(msg.sender, recipient, tokenContract.tokenOfOwnerByIndex(msg.sender, 0));
        }
    }

    function getAllTokenIds(IERC721Enumerable tokenContract) external view returns (uint256[] memory) {
        uint256 balance = tokenContract.balanceOf(msg.sender);
        uint256[] memory tokenIds = new uint256[](balance);
        for (uint256 index; index < balance; index++) {
            tokenIds[index] = tokenContract.tokenOfOwnerByIndex(msg.sender, index);
        }
        return tokenIds;
    }

    function bulkTransferByTokenIds(IERC721 tokenContract, address recipient, uint256[] calldata tokenIds) external {
        for (uint256 index; index < tokenIds.length; index++) {
            tokenContract.transferFrom(msg.sender, recipient, tokenIds[index]);
        }
    }
}

