// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.6.0;

import "./shared_Gap10000.sol";

contract $Gap10000 is Gap10000 {
    bytes32 public __hh_exposed_bytecode_marker = "hardhat-exposed";

    constructor() {}

    receive() external payable {}
}

