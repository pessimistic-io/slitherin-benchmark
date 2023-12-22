// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "./Ownable.sol";
import "./Strings.sol";

import "./IStrategBlockRegistry.sol";
import {IStrategCommonBlock} from "./IStrategCommonBlock.sol";

/**
 * Errors
 */
error NotOwner();
error NotDeployer();
error BlockAlreadyExists();

/**
 * @title StrategBlockRegistry
 * @author
 * @notice A contract for registering strategy blocks.
 */
contract StrategBlockRegistry is
    Ownable(msg.sender),
    IStrategyBlockRegistry //@note TO CHECK AGAIN INIT ADRESS
{
    uint256 public blocksLength;
    mapping(address => StrategBlockData) public blocks;

    constructor() {}

    /**
     *  @notice Adds multiple strategy blocks to the registry.
     *  @param _blocks Array of strategy block addresses to be added.
     *  @param _names Array of names corresponding to the strategy blocks.
     */
    function addBlocks(address[] memory _blocks, string[] memory _names) external {
        if (owner() != msg.sender) revert NotOwner();

        for (uint256 i = 0; i < _blocks.length; i++) {
            if (blocks[_blocks[i]].enabled) revert BlockAlreadyExists();
            blocks[_blocks[i]] = StrategBlockData({enabled: true, name: _names[i]});

            emit NewBlock(_blocks[i], msg.sender, _names[i]);
        }

        blocksLength = blocksLength + _blocks.length;
    }

    /**
     * @notice Removes multiple strategy blocks from the registry.
     * @param _blocks Array of strategy block addresses to be removed.
     */
    function removeBlocks(address[] memory _blocks) external {
        
        if (owner() != msg.sender) revert NotOwner();
        
        for (uint256 i = 0; i < _blocks.length; i++) {
            StrategBlockData storage b = blocks[_blocks[i]];
            if (b.enabled) {
                delete b.enabled;
                delete b.name;

                emit RemoveBlock(_blocks[i]);
                blocksLength = blocksLength - 1;
            }
        }
    }

    /**
     * @notice Checks if the given strategy blocks are valid (enabled).
     * @param _blocks _blocks Array of strategy block addresses to be checked.
     * @return A boolean indicating whether all the blocks are valid.
     */
    function blocksValid(address[] memory _blocks) external view returns (bool) {
        for (uint256 i = 0; i < _blocks.length; i++) {
            StrategBlockData storage b = blocks[_blocks[i]];
            if (!b.enabled) {
                return false;
            }
        }

        return true;
    }

    /**
     * @notice Retrieves the data of the given strategy blocks.
     * @param _blocks Array of strategy block addresses.
     * @return An array of StrategBlockData containing the data of the strategy blocks.
     */
    function getBlocks(address[] memory _blocks) external view returns (StrategBlockData[] memory) {
        StrategBlockData[] memory blocksArray = new StrategBlockData[](
            _blocks.length
        );

        for (uint256 i = 0; i < _blocks.length; i++) {
            blocksArray[i] = blocks[_blocks[i]];
        }

        return blocksArray;
    }
}

