// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.0;

import {IFootyDescriptor} from "./IFootyDescriptor.sol";

interface IFootySeeder {
    struct FootySeed {
        uint32 background;
        uint32 kit;
        uint32 head;
        uint32 glasses;
        uint32 number;
    }

    function generateFootySeed(uint256 tokenId, IFootyDescriptor descriptor)
        external
        view
        returns (FootySeed memory);
}

