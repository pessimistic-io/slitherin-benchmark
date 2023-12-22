// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

library ChainUtils {
    function getChainId() internal view returns (uint256) {
        uint256 chainId;
        assembly {
            chainId := chainid()
        }
        return chainId;
    }
}

