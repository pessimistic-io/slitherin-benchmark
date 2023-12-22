// SPDX-License-Identifier: GPL-3.0

import {Strings} from "./Strings.sol";

import "./Base64.sol";

import {IFootyDescriptor} from "./IFootyDescriptor.sol";

pragma solidity ^0.8.0;

interface IFootySeeder {
    struct FootySeed {
        uint256 background;
        uint256 kit;
        uint256 head;
        uint256 glasses;
        uint256 number;
    }

    function generateFootySeed(uint256 tokenId, IFootyDescriptor descriptor)
        external
        view
        returns (FootySeed memory);
}

contract FootySeeder is IFootySeeder {
    function generateFootySeed(uint256 tokenId, IFootyDescriptor descriptor)
        external
        view
        override
        returns (FootySeed memory)
    {
        uint256 pseudoRandom = uint256(
            keccak256(abi.encodePacked(blockhash(block.number - 1), tokenId))
        );

        uint256 headIndex;

        if ((pseudoRandom % 100) < 3) {
            headIndex = descriptor.getLegendaryHead(
                (pseudoRandom / 6) % descriptor.legendaryHeadCount()
            );
        } else if ((pseudoRandom % 100) < 15) {
            headIndex = descriptor.getRareHead(
                (pseudoRandom / 7) % descriptor.rareHeadCount()
            );
        } else {
            headIndex = descriptor.getCommonHead(
                (pseudoRandom / 8) % descriptor.commonHeadCount()
            );
        }

        return
            FootySeed({
                background: (pseudoRandom) % descriptor.backgroundCount(),
                kit: (pseudoRandom >> 96) % descriptor.kitCount(),
                head: headIndex,
                glasses: (pseudoRandom >> 144) % descriptor.glassesCount(),
                number: ((pseudoRandom >> 192) % 11) + 1
            });
    }
}

