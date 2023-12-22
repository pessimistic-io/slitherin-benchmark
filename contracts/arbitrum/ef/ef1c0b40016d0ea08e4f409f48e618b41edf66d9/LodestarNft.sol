// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

import {ERC721} from "./ERC721.sol";
import {Ownable} from "./Ownable.sol";

contract LodestarNft is ERC721, Ownable {
    uint256 public tokenCount;

    constructor() ERC721("LodestarNFT", "LODE") {
        tokenCount = 0;
    }

    function mint(address _to) public onlyOwner {
        _mint(_to, tokenCount);
        tokenCount += 1;
    }
}

