// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

interface IERC721Receiver {
    function onERC721Received(
        address operator,
        address from,
        uint256 tokenID,
        bytes calldata data
    ) external returns (bytes4);
}

