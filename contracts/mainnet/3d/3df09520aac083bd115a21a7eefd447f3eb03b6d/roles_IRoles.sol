// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.6.0;

import "./roles_IRoles.sol";

abstract contract $IRoles is IRoles {
    bytes32 public __hh_exposed_bytecode_marker = "hardhat-exposed";

    constructor() {}

    receive() external payable {}
}

