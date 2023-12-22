// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface ITldNameResolver {
    event TldNameChanged(bytes32 indexed node, uint256 identifier, string name);

    function tldName(bytes32 node, uint256 identifier) external view returns (string memory);

}

