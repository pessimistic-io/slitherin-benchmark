// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

import "./ERC721.sol";
import "./Ownable.sol";

contract RootsAndRoofsNFT is ERC721, Ownable {
    constructor(address owner_) ERC721("Roots&Roofs G.ART Berlin Collection", "GART R&R") {

        _transferOwnership(owner_);

        for(uint8 i = 1; i < 30; i++) {
            _mint(owner_, i);
        }
    }

    function _baseURI() internal view override returns (string memory) {
        return "ipfs://QmNTYizWuuUQJLVmbEgPkyWzgetLLcteaXrSTdHuMmB67o/";
    }

    function tokenURI(uint256 tokenId_) public view virtual override returns (string memory) {
        return string(abi.encodePacked(super.tokenURI(tokenId_), ".json"));
    }
}

