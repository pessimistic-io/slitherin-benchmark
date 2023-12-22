// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

interface IMerkle {
    function hash(uint256 a, uint256 b) external view returns (uint256);

    function insert(uint256 leaf) external returns (uint256);

    function getRootHash() external view returns (uint256);

    function rootHashExists(uint256 _root) external view returns (bool);

    // every node in the merkle tree is assigned an index, this is what's being referred to here
    function getSiblingIndex(uint256 index) external pure returns (uint256);

    function findAndRemove(uint256 dataToRemove, uint256 index) external;

    function logarithm2(uint256 x) external pure returns (uint256);
}

