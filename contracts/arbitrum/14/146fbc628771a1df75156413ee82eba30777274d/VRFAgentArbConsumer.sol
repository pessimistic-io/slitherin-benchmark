// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./VRFAgentConsumer.sol";

interface ArbSys {
    /**
    * @notice Get Arbitrum block number (distinct from L1 block number; Arbitrum genesis block has block number 0)
    * @return block number as int
     */
    function arbBlockNumber() external view returns (uint);
}

/**
 * @title VRFAgentArbConsumer
 * @author PowerPool
 */
contract VRFAgentArbConsumer is VRFAgentConsumer {
    constructor(address agent_) VRFAgentConsumer(agent_) {
    }

    function getLastBlockHash() public override view returns (uint256) {
        uint256 blockNumber = ArbSys(address(100)).arbBlockNumber();
        if (blockNumber == 0) {
          blockNumber = block.number;
        }
        return uint256(blockhash(blockNumber - 1));
    }
}

