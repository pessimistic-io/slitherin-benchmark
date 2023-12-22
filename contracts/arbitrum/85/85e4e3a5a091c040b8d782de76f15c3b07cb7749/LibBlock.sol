// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.20;

import "./IERC20.sol";
import "./SafeERC20.sol";
import "./DataTypes.sol";

error StrategyEnterReverted(address _block, uint256 _index, bytes _data);
error StrategyExitReverted(address _block, uint256 _index, bytes _data);
error OracleEnterReverted(address _block, uint256 _index, bytes _data);
error OracleExitReverted(address _block, uint256 _index, bytes _data);
error HarvestReverted(address _block, uint256 _index, bytes _data);

library LibBlock {
    using SafeERC20 for IERC20;

    bytes32 constant STRATEGY_BLOCKS_STORAGE_POSITION = keccak256("strategy.blocks.strateg.io");
    bytes32 constant HARVEST_BLOCKS_STORAGE_POSITION = keccak256("harvest.blocks.strateg.io");
    bytes32 constant DYNAMIC_BLOCKS_STORAGE_POSITION = keccak256("dynamic.blocks.strateg.io");

    struct BlocksStorage {
        mapping(uint256 => bytes) storagePerIndex;
    }

    struct DynamicBlocksStorage {
        mapping(uint256 => bytes) dynamicStorePerIndex;
    }

    /**
     * Dynamic storage part
     */
    function dynamicBlocksStorage() internal pure returns (DynamicBlocksStorage storage ds) {
        bytes32 position = DYNAMIC_BLOCKS_STORAGE_POSITION;
        assembly {
            ds.slot := position
        }
    }

    function setupDynamicBlockData(uint256 _index, bytes memory _data) internal {
        dynamicBlocksStorage().dynamicStorePerIndex[_index] = _data;
    }

    function purgeDynamicBlockData(uint256 _index) internal {
        delete (dynamicBlocksStorage().dynamicStorePerIndex[_index]);
    }

    function getDynamicBlockData(uint256 _index) internal view returns (bytes memory) {
        return dynamicBlocksStorage().dynamicStorePerIndex[_index];
    }

    /**
     * Strategy part
     */
    function strategyBlocksStorage() internal pure returns (BlocksStorage storage ds) {
        bytes32 position = STRATEGY_BLOCKS_STORAGE_POSITION;
        assembly {
            ds.slot := position
        }
    }

    function getStrategyStorageByIndex(uint256 _index) internal view returns (bytes memory) {
        BlocksStorage storage store = strategyBlocksStorage();
        return store.storagePerIndex[_index];
    }

    function setupStrategyBlockData(uint256 _index, bytes memory _data) internal {
        BlocksStorage storage store = strategyBlocksStorage();
        store.storagePerIndex[_index] = _data;
    }

    function executeStrategyEnter(address _block, uint256 _index) internal {
        (bool success, bytes memory _data) = _block.delegatecall(abi.encodeWithSignature("enter(uint256)", _index));

        if (!success) revert StrategyEnterReverted(_block, _index, _data);
    }

    function executeStrategyExit(address _block, uint256 _index, uint256 _percent) internal {
        (bool success, bytes memory _data) =
            _block.delegatecall(abi.encodeWithSignature("exit(uint256,uint256)", _index, _percent));

        if (!success) revert StrategyExitReverted(_block, _index, _data);
    }

    /**
     * Harvest part
     */
    function harvestBlocksStorage() internal pure returns (BlocksStorage storage ds) {
        bytes32 position = HARVEST_BLOCKS_STORAGE_POSITION;
        assembly {
            ds.slot := position
        }
    }

    function getHarvestStorageByIndex(uint256 _index) internal view returns (bytes memory) {
        BlocksStorage storage store = harvestBlocksStorage();
        return store.storagePerIndex[_index];
    }

    function setupHarvestBlockData(uint256 _index, bytes memory _data) internal {
        BlocksStorage storage store = harvestBlocksStorage();
        store.storagePerIndex[_index] = _data;
    }

    function executeHarvest(address _block, uint256 _index) internal {
        (bool success, bytes memory _data) = _block.delegatecall(abi.encodeWithSignature("harvest(uint256)", _index));

        if (!success) revert HarvestReverted(_block, _index, _data);
    }
}

