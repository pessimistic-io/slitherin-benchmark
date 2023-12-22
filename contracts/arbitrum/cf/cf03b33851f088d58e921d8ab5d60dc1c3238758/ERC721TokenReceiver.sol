// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

abstract contract ERC721TokenReceiver {
    function onERC721Received(address, address, uint256, bytes calldata)
        external
        pure
        returns (bytes4)
    {
        return ERC721TokenReceiver.onERC721Received.selector;
    }
}

