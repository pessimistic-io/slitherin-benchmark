// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.6.0;

import "./interfaces_IEtherspotWallet.sol";
import "./IEntryPoint.sol";

abstract contract $IEtherspotWallet is IEtherspotWallet {
    bytes32 public __hh_exposed_bytecode_marker = "hardhat-exposed";

    constructor() {}
}

