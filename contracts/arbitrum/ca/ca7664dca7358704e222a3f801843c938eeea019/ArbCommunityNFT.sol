//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "./ArbNFT.sol";
import "./Ownable.sol";

contract ArbCommunityNFT is ArbNFT, Ownable {
    constructor() ArbNFT("ArbCommunityNFTs", "ACNFT") public {
    }
    function mintCommunityNFT(address to, string memory uri) external onlyOwner {
        mint(to, uri);
    }
    function batchMintCommunityNft(address[] memory tos, string[] memory uris) external onlyOwner {
        _batchMint(tos,uris);
    }

}
