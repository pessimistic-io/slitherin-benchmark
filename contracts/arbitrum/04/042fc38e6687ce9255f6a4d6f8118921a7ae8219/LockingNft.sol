// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./ERC721Upgradeable.sol";
import "./Counters.sol";
import "./OwnableUpgradeable.sol";

contract LockingNft is ERC721Upgradeable, OwnableUpgradeable {
    using Counters for Counters.Counter;
    Counters.Counter private tokenIds;
    Counters.Counter private activeNfts;

    function initialize(
        address _owner,
        string memory name_,
        string memory symbol_
    ) public initializer {
        __ERC721_init(name_, symbol_);
        OwnableUpgradeable.__Ownable_init();
        _transferOwnership(_owner);
    }

    function mint(
        address _mintTo
    ) external onlyOwner returns (uint256 tokenId) {
        tokenId = tokenIds.current();
        _safeMint(_mintTo, tokenId);
        tokenIds.increment();
        activeNfts.increment();
        return tokenId;
    }

    function _baseURI() internal pure override returns (string memory) {
        return "ipfs://QmWmvTJmJU3pozR9ZHFmQC2DNDwi2XJtf3QGyYiiagFSWb";
    }
}

