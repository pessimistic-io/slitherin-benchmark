// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.6.0;

import "./wallet_EtherspotWalletFactory.sol";

contract $EtherspotWalletFactory is EtherspotWalletFactory {
    bytes32 public __hh_exposed_bytecode_marker = "hardhat-exposed";

    constructor() {}

    function $getInitializer(IEntryPoint entryPoint,address owner) external pure returns (bytes memory ret0) {
        (ret0) = super.getInitializer(entryPoint,owner);
    }

    receive() external payable {}
}

