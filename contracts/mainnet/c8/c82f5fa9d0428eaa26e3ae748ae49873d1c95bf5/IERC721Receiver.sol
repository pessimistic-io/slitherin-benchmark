// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @title ERC721S token receiver interface
 * @dev Interface for any contract that wants to support safeTransfers
 * from ERC721S asset contracts.
 */
interface IERC721Receiver {
    /**
     * @dev Whenever an {IERC721S} `tokenId` token is transferred to this contract via {IERC721S-safeTransferFrom}
     * by `operator` from `from`, this function is called.
     *
     * It must return its Solidity selector to confirm the token transfer.
     * If any other value is returned or the interface is not implemented by the recipient, the transfer will be reverted.
     *
     * The selector can be obtained in Solidity with `IERC721S.onERC721Received.selector`.
     */
    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external returns (bytes4);
}

