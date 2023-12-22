// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./IArbSys.sol";

library ChainUtils {

    uint256 constant public ARBITRUM_MAINNET = 42161;
    uint256 constant public ARBITRUM_GOERLI = 421614;
    IArbSys constant public ARB_SYS = IArbSys(address(100));

    function getBlockNumber() internal view returns (uint) {
        if (block.chainid == ARBITRUM_MAINNET || block.chainid == ARBITRUM_GOERLI) {
            return ARB_SYS.arbBlockNumber();
        }

        return block.number;
    }
}

