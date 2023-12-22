// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IArbERC721 {
    function bridgeMint(
        address account,
        uint256 tokenId,
        bytes calldata data
    ) external;

    function l1Address() external view returns (address);
}

