// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./ERC721URIStorage.sol";


// @title Frog
// It is Wednesday, my dudes
contract Lyagushka is ERC721URIStorage {

    uint256 public totalSupply = 1;

    // mint token 1 to the msg.sender
    constructor() ERC721("Lyaguga", "LGSHK") {
        _mint(msg.sender, 1);

        _setTokenURI(1, "https://raw.githubusercontent.com/Lyagushe4ka/useless/main/LyagugMetadata.json");
    }
}
