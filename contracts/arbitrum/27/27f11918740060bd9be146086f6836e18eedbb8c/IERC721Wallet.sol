// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.6.0;

import "./interfaces_IERC721Wallet.sol";

abstract contract $IERC1271Wallet is IERC1271Wallet {
    bytes32 public __hh_exposed_bytecode_marker = "hardhat-exposed";

    constructor() {}

    receive() external payable {}
}

