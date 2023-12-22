// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

contract Transfer {
    function transfer(address payable to) external payable {
        require(msg.value > 0, "Insufficient balance");
        to.transfer(msg.value);
    }
}