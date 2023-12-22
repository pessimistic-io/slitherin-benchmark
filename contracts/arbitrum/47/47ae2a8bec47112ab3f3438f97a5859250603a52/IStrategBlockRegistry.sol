// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

interface IStrategyBlockRegistry {
    struct StrategBlockData {
        bool enabled;
        string name;
    }

    event NewBlock(address addr, address deployer, string name);

    event RemoveBlock(address addr);

    function addBlocks(address[] memory _blocks, string[] memory _names) external;
    function removeBlocks(address[] memory _blocks) external;
    function blocksValid(address[] memory _blocks) external view returns (bool);
    function getBlocks(address[] memory _blocks) external view returns (StrategBlockData[] memory);
}

