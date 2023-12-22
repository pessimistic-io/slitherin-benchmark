// SPDX-License-Identifier: BUSL-1.1

pragma solidity >=0.4.21 <0.9.0;

interface ArbSys {
    /**
     * @notice Get Arbitrum block number (distinct from L1 block number; Arbitrum genesis block has block number 0)
     * @return block number as int
     */
    function arbBlockNumber() external view returns (uint256);
}

