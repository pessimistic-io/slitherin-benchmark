// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.6.0;

import "./interfaces_IAccessController.sol";

abstract contract $IAccessController is IAccessController {
    bytes32 public __hh_exposed_bytecode_marker = "hardhat-exposed";

    constructor() {}

    receive() external payable {}
}

