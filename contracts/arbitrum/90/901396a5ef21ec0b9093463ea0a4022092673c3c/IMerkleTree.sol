//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

interface IMerkleTree {
    function verify(address recipient, bytes32[] memory proof) external;
}

