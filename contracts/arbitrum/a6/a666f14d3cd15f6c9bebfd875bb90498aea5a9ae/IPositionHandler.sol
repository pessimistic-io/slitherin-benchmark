// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

import {Position, PositionBond, OrderInfo, OrderType} from "./Structs.sol";

interface IPositionHandler {
    function getBond(bytes32 _key) external view returns (PositionBond memory);

    function openNewPosition(
        bytes32 _key,
        bool _isLong, 
        uint256 _posId,
        bytes memory _data,
        uint256[] memory _params,
        uint256[] memory _prices, 
        address[] memory _path,
        bool _isDirectExecuted
    ) external;

    function modifyPosition(
        bytes32 _key, 
        uint256 _txType, 
        bytes memory _data,
        address[] memory path,
        uint256[] memory prices
    ) external;

    function setPriceAndExecuteInBatch(
        bytes32[] memory _keys, 
        bool[] memory _isLiquidates, 
        address[][] memory _batchPath,
        uint256[][] memory _batchPrices
    ) external;
}
