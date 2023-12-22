// SPDX-License-Identifier: Business Source License 1.1
pragma solidity ^0.8.19;

import "./IdType.sol";

abstract contract ILootBoxStorage {
    struct Scope {
        uint32 begin;
        uint32 end;
        uint64 maxSupply;
        uint8 alwaysBurn;
        uint120 reserved;
    }

    struct Counters {
        // holds the next token id
        IdType nextBoxId;
        // how many unsatisfied request are
        uint16 claimRequestCounter;
        // empty (jackpot) loot boxes global counter
        uint32 emptyCounter;
        // boost adding to supply, e.g: 5 lbs x 3 boost = 5 max supply, but 15 total income
        // 15-5 = 10 - is the boost adding
        uint32 boostAdding;
        uint112 reserved2;
        // if it requires to add more rarities, use reserved space (up to 16 rarities)
        bytes32[2] reserved3;
    }

    function _nextTokenId() internal virtual returns (IdType) {
        return _nextTokenId(1);
    }

    function _nextTokenId(uint count) internal virtual returns (IdType);

    function _totalSupplyWithBoost() internal virtual view returns (uint64);

    function _scope() internal view virtual returns (Scope storage);

    function _scope(Scope memory scope) internal virtual;

    function _counters() internal view virtual returns (Counters memory);

    function _addEmptyCounter(int32 amount) internal virtual;

    function _increaseClaimRequestCounter(uint16 amount) internal virtual;

    function _decreaseClaimRequestCounter(uint16 amount) internal virtual;

    function _addBoostAdding(uint32 amount) internal virtual;
}
