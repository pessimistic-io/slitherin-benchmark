// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;
import "./SharksStaking.sol";

contract SharksTransferControl {
    SharksStaking public sharksStaking;

    constructor(address sharksStakingAddress_) {
        sharksStaking = SharksStaking(sharksStakingAddress_);
    }

    function sharkCanBeTransferred(uint tokenId_) public view returns (bool) {
        return sharksStaking.sharkCanBeTransferred(tokenId_);
    }
}
