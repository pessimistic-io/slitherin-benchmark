// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.6.0;

import "./interfaces_IEtherspotWalletFactory.sol";

abstract contract $IEtherspotWalletFactory is IEtherspotWalletFactory {
    bytes32 public __hh_exposed_bytecode_marker = "hardhat-exposed";

    constructor() {}

    receive() external payable {}
}

