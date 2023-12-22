// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./ERC721Enumerable.sol";
import "./Strings.sol";

contract GrilloNFT is ERC721Enumerable {
    using Strings for uint256;

    constructor() ERC721("GRILLO", "GRILLO NFT") {}

    function mint() public {
        require(totalSupply() < 10000, "Unavailable");
       _safeMint(_msgSender(), totalSupply());
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_exists(tokenId), "Nonexistent token");
        return string(abi.encodePacked(_baseURI(), tokenId.toString()));
    }

    function _baseURI() internal pure override returns (string memory) {
        return "https://www.irreparabile.xyz/grilloNFT/";
    }
}
