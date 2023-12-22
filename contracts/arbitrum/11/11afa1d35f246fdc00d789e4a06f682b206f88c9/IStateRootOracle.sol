// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

interface IStateRootOracle {
    struct BlockInfo {
        bytes32 stateRootHash;
        uint40 timestamp;
    }

    function getBlockInfo(uint256 blockNumber) external view returns (BlockInfo memory _blockInfo);
}

