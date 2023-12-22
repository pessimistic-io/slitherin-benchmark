// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.13;

interface IRNG {
    function getSponsorWallet() external view returns (address);
    function makeRequestUint256() external returns (bytes32);
    function makeRequestUint256Array(uint256 size) external returns (bytes32);
}

