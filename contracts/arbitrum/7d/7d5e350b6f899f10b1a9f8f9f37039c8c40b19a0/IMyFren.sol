// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IMyFren {
    function pendingEth(uint256 petId) external returns (uint256);
}
