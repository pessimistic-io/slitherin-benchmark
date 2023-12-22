// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./Ownable.sol";
import "./Counters.sol";
import "./RandomNumberForAirdrop.sol";
import "./IOpenBlox.sol";

struct BatchBlox {
    address recipient;
    uint8 amount;
    uint8 raceId;
}

contract AirdropS2 is Ownable, RandomNumberForAirdrop {
    uint256 private constant CIRCULATION = 5000;
    uint256 private constant TOKEN_ID_START = 2548;
    uint256 private constant TOKEN_ID_END = 7547;

    using Counters for Counters.Counter;
    Counters.Counter private _tokenIdTracker;

    address public nftAddress;

    constructor(address _nftAddress) {
        require(_nftAddress != address(0), "Presale: invalid nft address");
        nftAddress = _nftAddress;
        _tokenIdTracker.set(TOKEN_ID_START, TOKEN_ID_END);
    }

    function mint(BatchBlox[] calldata bloxes) external onlyOwner {
        _mint(bloxes);
    }

    function _mint(BatchBlox[] calldata bloxes) internal {
        for (uint8 i = 0; i < bloxes.length; ++i) {
            require(bloxes[i].raceId < 6, "Presale: invalid raceId");
            for (uint8 j = 0; j < bloxes[i].amount; ++j) {
                uint256 tokenId = _tokenIdTracker.current();
                uint256 genes = _generateRandomGenes(tokenId, uint16(i) * 37, bloxes[i].raceId);
                uint256 ancestorCode = _geneerateAncestorCode(tokenId);
                IOpenBlox(nftAddress).mintBlox(
                    tokenId, // tokenId
                    bloxes[i].recipient, // receiver
                    genes, // genes
                    block.timestamp, // bornAt
                    0, // generation
                    0, // parent0Id
                    0, // parent1Id
                    ancestorCode, // ancestorCode
                    0 // reproduction
                );
                _tokenIdTracker.increment();
            }
        }
    }
}

