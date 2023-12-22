// SPDX-License-Identifier: Business Source License 1.1
pragma solidity ^0.8.19;

type StateType is uint8;

StateType constant MYSTERY_STATE = StateType.wrap(StateTypeLib.NFT_MYSTERY);
StateType constant EMPTY_STATE = StateType.wrap(StateTypeLib.NFT_EMPTY);

library StateTypeLib {
    uint8 internal constant NFT_MYSTERY = 0;
    uint8 internal constant NFT_EMPTY = 1;
    // 4..31 reserved for the future usage
    uint8 internal constant NFT_RARITY_0 = 32;

    function toRarity(StateType state) internal pure returns (uint) {
        uint8 val = StateType.unwrap(state);
        return val - NFT_RARITY_0;
    }

    function toState(uint rarity) internal pure returns (StateType) {
        return StateType.wrap(uint8(rarity) + NFT_RARITY_0);
    }

    function isRare(StateType state) internal pure returns (bool) {
        return StateType.unwrap(state) >= NFT_RARITY_0;
    }

    function isMystery(StateType state) internal pure returns (bool) {
        return StateType.unwrap(state) == NFT_MYSTERY;
    }

    function isNotMystery(StateType state) internal pure returns (bool) {
        return StateType.unwrap(state) != NFT_MYSTERY;
    }

    function isEmpty(StateType state) internal pure returns (bool) {
        return StateType.unwrap(state) == NFT_EMPTY;
    }
}

