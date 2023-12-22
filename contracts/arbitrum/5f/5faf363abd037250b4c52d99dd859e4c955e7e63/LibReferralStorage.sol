// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

struct ReferralStorage {
    mapping(uint256 => address) petToRef;
}

library LibReferralStorage {
    bytes32 internal constant DIAMOND_REFERRAL_STORAGE_POSITION =
        keccak256("diamond.referral.v1.storage");

    function referralStorage()
        internal
        pure
        returns (ReferralStorage storage ds)
    {
        bytes32 position = DIAMOND_REFERRAL_STORAGE_POSITION;
        assembly {
            ds.slot := position
        }
    }
}
