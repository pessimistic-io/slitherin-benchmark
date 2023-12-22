// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

contract RandomNumberForAirdrop {
    function _generateRandomMystricId(uint256 tokenId, uint16 sequence) internal view returns (uint8) {
        uint16[3] memory weight = [9989, 9999, 10000];
        uint256 random1 = uint256(keccak256(abi.encodePacked(msg.sender, tokenId, sequence, blockhash(block.number - 1), block.coinbase, block.difficulty)));
        uint16 random2 = uint16(random1 % (10000));
        for (uint8 i = 0; i < 3; ++i) {
            if (random2 < weight[i]) return i;
        }
        return 2;
    }

    function _generateRandomPartsId(uint256 tokenId, uint16 sequence) internal view returns (uint8) {
        uint16[6] memory weight = [1990, 3980, 5970, 7960, 9950, 10000];
        uint256 random1 = uint256(keccak256(abi.encodePacked(msg.sender, tokenId, sequence, blockhash(block.number - 1), block.coinbase, block.difficulty)));
        uint16 random2 = uint16(random1 % 10000);
        for (uint8 i = 0; i < 6; ++i) {
            if (random2 < weight[i]) return i;
        }
        return 5;
    }

    function _generateRandomParts(
        uint256 tokenId,
        uint16 sequence,
        uint8 raceId
    ) internal view returns (uint8[13] memory) {
        uint8[13] memory randoms = [uint8(0), 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
        // randoms:
        //   0, 1: head
        //   2, 3: body
        //   4, 5: horn
        //   6, 7: back
        //   8, 9: arms
        //   10, 11: legs
        //   12: race

        // random from [0,1,2,3,4,5]
        randoms[12] = raceId;
        for (uint8 i = 0; i < 6; ++i) {
            // race: range = [0,1,2], rate = [9989,10,1], weight = [9989,9999,10000]
            randoms[i * 2] = _generateRandomMystricId(tokenId, sequence + i * 6 + 1);
            // range = [0,1,2,3,4,5], rate = [1990,1990,1990,1990,1990,50], weight = [1990,3980,5970,7960,9950,10000]
            randoms[i * 2 + 1] = _generateRandomPartsId(tokenId, sequence + i * 6 + 5);
        }
        return randoms;
    }

    function _generateRandomGenes(
        uint256 tokenId,
        uint16 sequence,
        uint8 raceId
    ) internal view returns (uint256 genes) {
        uint8[13] memory randoms = _generateRandomParts(tokenId, sequence, raceId);
        for (uint8 i = 0; i < 6; ++i) {
            genes = genes * 0x100000000;
            uint256 unit = randoms[12] * 0x20 + randoms[i * 2 + 1];
            uint256 gene = randoms[i * 2] * 0x40000000 + unit * 0x100401;
            genes = genes + gene;
        }
        genes = genes * 0x10000000000000000;
        return genes;
    }

    function _geneerateAncestorCode(uint256 tokenId) internal pure returns (uint256 ancestorCode) {
        return tokenId * 0x1000100010001000100010001000100010001000100010001000100010001;
    }
}

