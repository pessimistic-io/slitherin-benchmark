// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {ERC721A} from "./ERC721A.sol";
import {Ownable} from "./Ownable.sol";

error MintLimitExceeded();

contract SampleNFT is ERC721A, Ownable {
    uint256 public constant MINT_LIMIT = 10;

    constructor() ERC721A("Sample Taiko NFT", "SAMPLE") {}

    function mint(uint256 qty) external payable {
        if (qty > MINT_LIMIT) revert MintLimitExceeded();
        _mint(msg.sender, qty);
    }

    function burn(uint256 tokenId) external {
        _burn(tokenId, true);
    }
}

