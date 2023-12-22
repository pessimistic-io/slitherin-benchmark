// Contract based on https://docs.openzeppelin.com/contracts/4.x/erc721
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import "./ERC721.sol";
import "./ERC721URIStorage.sol";
import "./Counters.sol";
import "./Ownable.sol";

contract GasLessNFT is ERC721URIStorage, Ownable {
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;
    uint256 private constant MAXLIMIT = 100;
    
    constructor(string memory collectionName, string memory collectionSymbol)
        ERC721(collectionName, collectionSymbol)
    {}

    function mintNFT(
        address recipient,
        string memory tokenURI,
        uint256 numNfts
    ) public {
        require(
            numNfts > 0 && numNfts <= MAXLIMIT,
            "Number of minting nfts are beyond limits"
        );
        for (uint256 i = 0; i < numNfts; i++) {
            _tokenIds.increment();
            uint256 newItemId = _tokenIds.current();
            _mint(recipient, newItemId);
            _setTokenURI(newItemId, tokenURI);
        }
    }
}

