// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

interface IAccount {
    function execute(address adapter, bytes calldata data) external payable returns (bytes memory returnData);
}

