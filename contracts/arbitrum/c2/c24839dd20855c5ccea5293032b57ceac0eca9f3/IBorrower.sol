// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface IBorrower {
    function executeOnFlashMint(uint256 amount, uint256 debt) external;
    function executeOnFlashMint(uint256 amount) external;
}
