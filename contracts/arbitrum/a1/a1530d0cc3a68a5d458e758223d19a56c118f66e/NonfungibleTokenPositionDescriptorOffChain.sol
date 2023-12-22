// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.7.6;
pragma abicoder v2;

import "./Strings.sol";

import "./INonfungibleTokenPositionDescriptor.sol";

/// @title Describes NFT token positions
contract NonfungibleTokenPositionDescriptorOffChain is INonfungibleTokenPositionDescriptor {
    using Strings for uint256;

    uint8 public VERSION = 1;

    string private _baseTokenURI;

    constructor(string memory baseTokenURI) {
        _baseTokenURI = baseTokenURI;
    }

    /// @inheritdoc INonfungibleTokenPositionDescriptor
    function tokenURI(INonfungiblePositionManager, uint256 tokenId) external view override returns (string memory) {
        return bytes(_baseTokenURI).length > 0 ? string(abi.encodePacked(_baseTokenURI, tokenId.toString())) : '';
    }
}

