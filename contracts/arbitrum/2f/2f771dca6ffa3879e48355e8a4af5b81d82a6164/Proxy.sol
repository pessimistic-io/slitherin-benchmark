// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.6.0;

import "./wallet_Proxy.sol";

contract $Proxy is Proxy {
    bytes32 public __hh_exposed_bytecode_marker = "hardhat-exposed";

    constructor(address _singleton) Proxy(_singleton) {}

    function $_IMPLEMENTATION_SLOT() external pure returns (bytes32) {
        return _IMPLEMENTATION_SLOT;
    }

    receive() external payable {}
}

