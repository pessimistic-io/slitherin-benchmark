// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.6;

import { INounsDescriptor } from "./INounsDescriptor.sol";

interface INounsSeeder {
    struct Seed {
        uint48 background;
        uint48 body;
        uint48 accessory;
        uint48 head;
        uint48 glasses;
        uint48 pants;
        uint48 shoes;
    }

    function generateSeed(uint256 nounId, INounsDescriptor descriptor, bytes32 pseudorandomHash) external view returns (Seed memory);
}
