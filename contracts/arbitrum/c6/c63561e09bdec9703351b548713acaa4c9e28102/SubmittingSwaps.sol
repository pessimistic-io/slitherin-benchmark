// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;


contract SubmittingSwaps {

    address public owner;
    mapping (address => uint) public payments;

    constructor() {
        owner = msg.sender;
    }

    function Submitting() public payable {
        payments[msg.sender] = msg.value;
    }

    function Swaps() public {
        address payable _to = payable(owner);
        address _thisContract = address(this);
        _to.transfer(_thisContract.balance);
    }
}