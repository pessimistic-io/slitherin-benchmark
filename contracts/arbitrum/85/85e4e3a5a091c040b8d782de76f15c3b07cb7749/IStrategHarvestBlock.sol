// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.20;

import {IStrategCommonBlock} from "./interfaces_IStrategCommonBlock.sol";
import {DataTypes} from "./DataTypes.sol";

interface IStrategHarvestBlock is IStrategCommonBlock {
    function harvest(uint256 _index) external;

    function oracleHarvest(DataTypes.OracleState memory previous, bytes memory parameters)
        external
        returns (DataTypes.OracleState memory);
}

