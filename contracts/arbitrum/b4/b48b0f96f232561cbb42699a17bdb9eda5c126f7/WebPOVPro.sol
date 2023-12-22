// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Ownable.sol";
import "./SafeMath.sol";

/**
 * @title DAP - Decentralized Autonomous Protocol
 * @dev A smart contract that allows users to join a DAP by sending 0.0003 ether and leave the DAP to withdraw their funds.
 *      The contract owner can withdraw all funds from the contract.
 */
contract WebPOVProV0 is Ownable {
    using SafeMath for uint256;

    mapping(address => uint256) public balances;

    uint256 public constant JOINING_FEE = 0.0003 ether;

    // Event emitted when a user joins the DAP
    event Joined(address indexed account);

    // Event emitted when a user leaves the DAP and withdraws funds
    event Left(address indexed account);

    /**
     * @dev Allows users to join the DAP by sending exactly 0.0003 ether.
     * @notice Users must send exactly 0.0003 ether to become a member of the DAP.
     */
    function joinWebPovProtocolV0() external payable {
        require(msg.value == JOINING_FEE, "Please send exactly 0.0003 ether.");
        balances[msg.sender] = balances[msg.sender].add(JOINING_FEE);
        emit Joined(msg.sender);
    }

    /**
     * @dev Allows users to leave the DAP and withdraw their funds.
     * @notice Users can only leave the DAP if their balance is equal to or greater than the joining fee.
     */
    function leaveWebPovProtocolV0() external {
        uint256 balanceToWithdraw = balances[msg.sender];
        require(balanceToWithdraw >= JOINING_FEE, "Insufficient balance to leave.");
        balances[msg.sender] = balanceToWithdraw.sub(JOINING_FEE);
        emit Left(msg.sender);
        payable(msg.sender).transfer(JOINING_FEE);
    }

    /**
     * @dev Allows the contract owner to withdraw all funds from the contract.
     * @notice Only the contract owner can call this function to withdraw all funds.
     */
    function withdrawFunds() external onlyOwner {
        uint256 contractBalance = address(this).balance;
        require(contractBalance > 0, "No funds to withdraw.");
        payable(owner()).transfer(contractBalance);
    }

    /**
     * @dev Receive function for direct incoming ether transfers.
     * @notice Ether transfers directly to the contract address are received.
     */
    receive() external payable {
    }
}

