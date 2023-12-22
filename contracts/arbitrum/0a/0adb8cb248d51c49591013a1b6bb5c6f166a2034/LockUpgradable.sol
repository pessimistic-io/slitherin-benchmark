// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

// Uncomment this line to use console.log
import "./Initializable.sol";
import "./console.sol";



contract LockUpgradable is Initializable {
    
    address payable public owner1;

    struct UserData {
        uint ethBalance;
        uint256 unlockTime;    
    }

    mapping(address => UserData) public userLocks;
 
    event LockMe(address account, uint lockedAmount, uint unlockTime);
    event Withdrawal(address account, uint withdrawalAmount, uint unlockTime);

    function initialize() public initializer {}

    function lockMe(uint _unlockTime) public payable {
        require(
            block.timestamp < _unlockTime,
            "Unlock time should be in the future"
        );
        // require(msg.value == 1 ether);
        userLocks[msg.sender] = UserData(msg.value, _unlockTime);

        emit LockMe(msg.sender, msg.value, _unlockTime);

        console.log("user added: %o, ethBalance: %o, unlockTime: %o", msg.sender, userLocks[msg.sender].ethBalance, userLocks[msg.sender].unlockTime);
    }

    // function addCluster(address id) returns(bool){
    //     if(clusterContract[id].isValue) throw; // duplicate key
    //     // insert this 
    //     return true; 
    // }


    function withdraw() public {
        // Uncomment this line, and the import of "hardhat/console.sol", to print a log in your terminal
        // console.log("Unlock time is %o and block timestamp is %o", unlockTime, block.timestamp);
        // require(userLocks[msg.sender]>0, "You aren't the owner");
        require(userLocks[msg.sender].unlockTime > 0, "You aren't the owner");

        require(userLocks[msg.sender].ethBalance > 0, "zero eth balance");

        require(block.timestamp >= userLocks[msg.sender].unlockTime, "You can't withdraw yet");

        uint withdrawalAmount = userLocks[msg.sender].ethBalance;

        payable(msg.sender).transfer(withdrawalAmount);

        userLocks[msg.sender].ethBalance = 0;

        emit Withdrawal(msg.sender, withdrawalAmount, userLocks[msg.sender].unlockTime);
    }
}

