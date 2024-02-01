// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.6.0;

import "./shared_FoundationTreasuryNode.sol";

contract $FoundationTreasuryNode is FoundationTreasuryNode {
    bytes32 public __hh_exposed_bytecode_marker = "hardhat-exposed";

    constructor(address payable _treasury) FoundationTreasuryNode(_treasury) {}

    receive() external payable {}
}

