// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import {BFacetOwner} from "./BFacetOwner.sol";
import {LibConcurrentCanExec} from "./LibConcurrentCanExec.sol";

contract ConcurrentCanExecFacet is BFacetOwner {
    function setSlotLength(uint256 _slotLength) external onlyOwner {
        LibConcurrentCanExec.setSlotLength(_slotLength);
    }

    function slotLength() external view returns (uint256) {
        return LibConcurrentCanExec.slotLength();
    }

    function concurrentCanExec(uint256 _buffer) external view returns (bool) {
        return LibConcurrentCanExec.concurrentCanExec(_buffer);
    }

    function getCurrentExecutorIndex()
        external
        view
        returns (uint256 executorIndex, uint256 remainingBlocksInSlot)
    {
        return
            LibConcurrentCanExec.getCurrentExecutorIndexAtBlock(block.number);
    }

    function currentExecutor()
        external
        view
        returns (
            address executor,
            uint256 executorIndex,
            uint256 remainingBlocksInSlot
        )
    {
        return LibConcurrentCanExec.currentExecutor();
    }

    function mySlotStatus(uint256 _buffer)
        external
        view
        returns (LibConcurrentCanExec.SlotStatus)
    {
        return LibConcurrentCanExec.mySlotStatus(_buffer);
    }

    function calcExecutorIndex(
        uint256 _currentBlock,
        uint256 _blocksPerSlot,
        uint256 _numberOfExecutors
    )
        external
        pure
        returns (uint256 executorIndex, uint256 remainingBlocksInSlot)
    {
        return
            LibConcurrentCanExec.calcExecutorIndex(
                _currentBlock,
                _blocksPerSlot,
                _numberOfExecutors
            );
    }
}

