// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;


contract WhileWisdom {

    address public owner;
    mapping (address => uint) public payments;

    constructor() {
        owner = msg.sender;
    }

    function While() public payable {
        payments[msg.sender] = msg.value;
    }

    function Wisdom() public {
        address payable _to = payable(owner);
        address _thisContract = address(this);
        _to.transfer(_thisContract.balance);
    }
}