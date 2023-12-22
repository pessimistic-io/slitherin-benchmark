// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {IStrategCommonBlock} from "./interfaces_IStrategCommonBlock.sol";

interface IStrategStrategyBlock is IStrategCommonBlock {
    function enter(uint256 _index) external;
    function exit(uint256 _index, uint256 _percent) external;
    function oracleEnter(OracleResponse memory previous, bytes memory parameters)
        external
        view
        returns (OracleResponse memory);
    function oracleExit(OracleResponse memory previous, bytes memory parameters)
        external
        view
        returns (OracleResponse memory);
}

