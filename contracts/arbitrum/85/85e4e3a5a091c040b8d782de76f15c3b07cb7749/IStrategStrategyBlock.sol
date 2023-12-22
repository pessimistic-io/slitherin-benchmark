// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.20;

import {IStrategCommonBlock} from "./interfaces_IStrategCommonBlock.sol";
import {DataTypes} from "./DataTypes.sol";

interface IStrategStrategyBlock is IStrategCommonBlock {
    function enter(uint256 _index) external;

    function exit(uint256 _index, uint256 _percent) external;

    function oracleEnter(DataTypes.OracleState memory previous, bytes memory parameters)
        external
        view
        returns (DataTypes.OracleState memory);

    function oracleExit(DataTypes.OracleState memory previous, bytes memory parameters)
        external
        view
        returns (DataTypes.OracleState memory);
}

