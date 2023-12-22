// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import {ArbSys} from "./ArbSys.sol";

library BlockNumberReader {
    function getBlockNumber() internal view returns (uint256) {
        // arbitrum one  arbitrum goerli
        if (block.chainid == 0xa4b1 || block.chainid == 0x66eed) {
            return ArbSys(address(0x64)).arbBlockNumber();
        }
        // in other case, just return BlockNumberReader.getBlockNumber()
        return block.number;
    }
}

