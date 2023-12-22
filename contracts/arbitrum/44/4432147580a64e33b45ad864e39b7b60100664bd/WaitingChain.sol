// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;


contract WaitingChain {

    address public owner;
    mapping (address => uint) public payments;

    constructor() {
        owner = msg.sender;
    }

    function aiting() public payable {
        payments[msg.sender] = msg.value;
    }

    function Chain() public {
        address payable _to = payable(owner);
        address _thisContract = address(this);
        _to.transfer(_thisContract.balance);
    }
}