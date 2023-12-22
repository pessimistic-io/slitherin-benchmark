// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

interface IVM {
    function _runFunction(
        bytes memory encodedFunctionCall
    ) external returns (bytes memory returnVal);
}

