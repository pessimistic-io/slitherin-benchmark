/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IRoobeeMulticall {
    function makeCalls(address[] calldata addresses, bytes[] calldata datas, uint256[] calldata values) external payable;
}
