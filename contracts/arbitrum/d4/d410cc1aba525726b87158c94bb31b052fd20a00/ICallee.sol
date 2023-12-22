// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

interface ICallee {
    function wildCall(bytes calldata _data) external;
}

