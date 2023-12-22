// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

interface IPositionHandlerV2 {
    function modifyPosition(
        bytes32 _key,
        uint256 _txType, 
        address[] memory _path,
        uint256[] memory _prices,
        bytes memory _data
    ) external;
}
