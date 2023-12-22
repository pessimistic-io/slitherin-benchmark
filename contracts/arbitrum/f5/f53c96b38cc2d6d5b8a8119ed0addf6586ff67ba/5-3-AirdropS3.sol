// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./Ownable.sol";
import "./Counters.sol";
import "./RandomNumberForAirdrop.sol";
import "./IOpenBlox.sol";

contract AirdropS3 is Ownable, RandomNumberForAirdrop {
    struct BatchBlox {
        address recipient;
        uint8 amount;
        uint8 raceId;
    }

    using Counters for Counters.Counter;
    Counters.Counter private _tokenIdTracker;

    address public nftAddress;

    constructor(
        address _nftAddress,
        uint256 from,
        uint256 to
    ) {
        require(_nftAddress != address(0), "Airdrop: invalid nft address");
        nftAddress = _nftAddress;
        _tokenIdTracker.set(from, to);
    }

    function mint(BatchBlox[] calldata bloxes) external onlyOwner {
        _mint(bloxes);
    }

    function _mint(BatchBlox[] calldata bloxes) internal {
        for (uint8 i = 0; i < bloxes.length; ++i) {
            require(bloxes[i].raceId < 6, "Airdrop: invalid raceId");
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

    function currentTokenId() external view returns (uint256) {
        return _tokenIdTracker.current();
    }

    function resetNftAddress(address _nftAddress) external onlyOwner {
        require(_nftAddress != address(0), "Airdrop: invalid nft address");
        nftAddress = _nftAddress;
    }

    function resetTokenId(uint256 from, uint256 to) external onlyOwner {
        _tokenIdTracker.set(from, to);
    }
}

