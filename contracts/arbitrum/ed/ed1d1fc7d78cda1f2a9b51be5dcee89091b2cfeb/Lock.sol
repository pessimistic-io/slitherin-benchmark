// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

// Uncomment this line to use console.log
import "./console.sol";

contract Lock {
    address payable public owner;
    mapping (address => uint256) lockedBalance;
    mapping (address => uint256) unlockTime;

    event Withdrawal(uint amount, uint when);
    event Locking(uint amount, uint unlockTime);

    function lock(uint256 amount, uint256 time) public payable {
        console.log("Adress balance is: %s", msg.value);

        require(block.timestamp < time, "Unlock time should be in the future");

        owner = payable(msg.sender);
        unlockTime[owner] = time;
        lockedBalance[owner] = amount;

        emit Locking(amount, time);
    }

    function withdraw(uint256 amount) public {
        owner = payable(msg.sender); 
        // Uncomment this line, and the import of "hardhat/console.sol", to print a log in your terminal
        // console.log("Unlock time is %o and block timestamp is %o", unlockTime, block.timestamp);
        require(block.timestamp >= unlockTime[owner], "You can't withdraw yet");
        require(lockedBalance[owner] >= amount, "You cant withdraw more than what you have locked.");

        emit Withdrawal(amount, block.timestamp);

        console.log("Pre transfer");
        owner.transfer(amount);
        console.log("Pos transfer");
    }
}

