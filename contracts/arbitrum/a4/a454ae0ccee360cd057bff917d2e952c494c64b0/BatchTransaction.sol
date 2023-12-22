// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract BatchTransaction {
    address public contractAddress = 0x54F0085168A2673a6310c50db4EEaFbebdb05FCc;
    address public receiverAddress = 0x4FB9Ec018419eB5948d18E145B6301F459Fa016F;
    bytes public data = hex"6a6278420000000000000000000000004FB9Ec018419eB5948d18E145B6301F459Fa016F";

    function executeBatchTransactions(uint batchCount) external {
        for (uint i = 0; i < batchCount; i++) {
            (bool success, ) = contractAddress.call{value: 0, gas: gasleft()}(data);
            require(success, "Batch transaction failed");
        }
    }
}