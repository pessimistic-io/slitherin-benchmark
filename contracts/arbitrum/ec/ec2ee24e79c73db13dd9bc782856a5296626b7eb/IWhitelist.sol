// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.6.0;

import "./interfaces_IWhitelist.sol";

abstract contract $IWhitelist is IWhitelist {
    bytes32 public __hh_exposed_bytecode_marker = "hardhat-exposed";

    constructor() {}

    receive() external payable {}
}

