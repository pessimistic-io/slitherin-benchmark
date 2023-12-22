// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {BitMaps} from "./BitMaps.sol";
import {Cue} from "./Cue.sol";

contract DiscoveryCue is Cue {
    using BitMaps for BitMaps.BitMap;

    constructor(
        string memory name_,
        string memory symbol_,
        uint256 maxSupply_
    ) Cue(name_, symbol_, maxSupply_) {}

    function mintBatch(
        address[] calldata wallets,
        uint256 cueType
    ) external onlyRole(MINTER_ROLE) nonReentrant {
        if (!_cueTypes.get(cueType)) {
            revert CueTypeNotSupported();
        }
        uint256 localNextId = nextTokenId;
        for (uint256 i = 0; i < wallets.length; ) {
            uint256 tokenId = localNextId++;
            _safeMint(wallets[i], tokenId);
            tokenCueTypes[tokenId] = cueType;
            emit CueMinted(wallets[i], tokenId, cueType);
            unchecked {
                i++;
            }
        }
        nextTokenId += localNextId;
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId,
        uint256 batchSize
    ) internal virtual override {
        require(from == address(0) || to == address(0), "DiscoveryCue: transfer not allowed");

        super._beforeTokenTransfer(from, to, tokenId, batchSize);
    }
}

