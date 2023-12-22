// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

abstract contract AERC721Receiver2 {
    /**
     * Always returns `IERC721Receiver.onERC721Received.selector`.
     */
    function onERC721Received(
        address,
        address,
        uint256,
        bytes memory
    ) public virtual returns (bytes4) {
        return this.onERC721Received.selector;
    }
}

