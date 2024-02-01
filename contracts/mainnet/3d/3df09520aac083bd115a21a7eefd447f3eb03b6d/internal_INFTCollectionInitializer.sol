// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.6.0;

import "./internal_INFTCollectionInitializer.sol";

abstract contract $INFTCollectionInitializer is INFTCollectionInitializer {
    bytes32 public __hh_exposed_bytecode_marker = "hardhat-exposed";

    constructor() {}

    receive() external payable {}
}

