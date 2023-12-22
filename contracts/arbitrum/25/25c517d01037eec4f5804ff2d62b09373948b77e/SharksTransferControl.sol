// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;
import "./SharksLocking.sol";

contract SharksTransferControl {
    SharksLocking public sharksLocking;

    constructor(address sharksLockingAddress_) {
        sharksLocking = SharksLocking(sharksLockingAddress_);
    }

    function sharkCanBeTransferred(uint tokenId_) public view returns (bool) {
        return sharksLocking.sharkCanBeTransferred(tokenId_);
    }
}
