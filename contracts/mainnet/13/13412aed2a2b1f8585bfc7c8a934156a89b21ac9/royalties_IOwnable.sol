// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.6.0;

import "./royalties_IOwnable.sol";

abstract contract $IOwnable is IOwnable {
    bytes32 public __hh_exposed_bytecode_marker = "hardhat-exposed";

    constructor() {}

    receive() external payable {}
}

