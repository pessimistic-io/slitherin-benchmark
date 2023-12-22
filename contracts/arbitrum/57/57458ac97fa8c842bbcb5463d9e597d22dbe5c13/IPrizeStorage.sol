// SPDX-License-Identifier: Business Source License 1.1
pragma solidity ^0.8.19;

import "./ProbabilityType.sol";

abstract contract IPrizeStorage {
    struct NftInfo {
        address collection;
        uint tokenId;
        Probability probability;
        uint32 chainId;
    }

    uint internal constant RARITIES = 3;
    uint32 internal constant MIN_PRIZE_INDEX = 1;
    uint32 internal constant RARITY_PRIZE_CAPACITY = 500_000;

    function _rarity(uint level) internal view virtual returns (RarityDef storage);
    function _rarity(uint level, Probability probability) internal virtual;

    function _prizes(uint32 id) internal view virtual returns (PrizeDef storage);
    function _delPrize(uint32 id) internal virtual;

    function _getPrizeIdByNft(address collection, uint tokenId) internal view virtual returns (uint32);
    function _addPrizeIdByNft(address collection, uint tokenId, uint32 id) internal virtual;
    function _removePrizeIdByNft(address collection, uint tokenId) internal virtual;

    uint32 public constant PRIZE_NFT = 2;

    struct RarityDef {
        Probability probability;
        uint32 lbCounter;
        uint32 head;
        uint32 tail;
        uint32 count;
        uint16 reserved1;
        uint32 reserved2;
        uint96 reserved3;
    }

    struct PrizeDef {
        address token;
        uint32 flags;
        uint32 left;
        uint32 right;
        uint value;

        Probability probability;
        uint32 chainId;
        uint96 reserved;
    }
}

