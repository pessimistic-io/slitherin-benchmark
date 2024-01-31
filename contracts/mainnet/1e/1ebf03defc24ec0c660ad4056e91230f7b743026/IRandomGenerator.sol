// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IRandomGenerator {
    function requestRandomNumber(uint256 tokenId, address user) external;
    function requestRandomNumber(uint256 tokenId, address user, uint32 callbackGasLimit_) external;
}
