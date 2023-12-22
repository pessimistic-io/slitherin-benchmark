// SPDX-License-Identifier: MIT

/// This contract deals with customer subscriptions for nft.

pragma solidity ^0.8.0;

import "./ERC721Enumerable.sol";
import "./Counters.sol";
import "./Ownable.sol";

/// @dev feature not enabled
contract CDXNFT is ERC721Enumerable, Ownable {
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;

    constructor() ERC721("cdx", "CDX") {
        _tokenIds.increment();
    }

    function mintCDX(address player) public returns (uint256) {
        uint256 newItemId = _tokenIds.current();
        _mint(player, newItemId);
        _tokenIds.increment();
        return newItemId;
    }
}

