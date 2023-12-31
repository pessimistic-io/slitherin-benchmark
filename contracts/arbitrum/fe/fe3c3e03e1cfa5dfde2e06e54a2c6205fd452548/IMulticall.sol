// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.17;

interface IMulticall {
    function multicall(bytes4[] calldata selectors, bytes[] calldata data) external;
}

