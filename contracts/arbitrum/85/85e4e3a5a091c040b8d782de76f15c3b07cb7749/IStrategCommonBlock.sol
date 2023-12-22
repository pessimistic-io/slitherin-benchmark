// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.20;

import {DataTypes} from "./DataTypes.sol";

interface IStrategCommonBlock {
    function ipfsHash() external view returns (string memory);

    function dynamicParamsInfo(
        DataTypes.BlockExecutionType _exec,
        bytes memory parameters,
        DataTypes.OracleState memory oracleState
    ) external view returns (bool, DataTypes.DynamicParamsType, bytes memory);
}

