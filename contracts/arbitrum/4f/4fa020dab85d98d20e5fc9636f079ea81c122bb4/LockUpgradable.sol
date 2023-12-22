// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

// Uncomment this line to use console.log
// import "hardhat/console.sol";
import "./Initializable.sol";

contract LockUpgradable is Initializable {
    uint public unlockTime;
    address payable public owner1;
 
    event Withdrawal(uint amount, uint when);

    function initialize(uint _unlockTime) public payable initializer {
        require(
            block.timestamp < _unlockTime,
            "Unlock time should be in the future"
        );

        unlockTime = _unlockTime;
        owner1 = payable(msg.sender);
    }

    function lockMe() public payable {
        // nothing at all
    }

    function withdraw() public {
        // Uncomment this line, and the import of "hardhat/console.sol", to print a log in your terminal
        // console.log("Unlock time is %o and block timestamp is %o", unlockTime, block.timestamp);

        require(block.timestamp >= unlockTime, "You can't withdraw yet");
        require(msg.sender == owner1, "You aren't the owner");

        emit Withdrawal(address(this).balance, block.timestamp);

        owner1.transfer(address(this).balance);
    }
}

