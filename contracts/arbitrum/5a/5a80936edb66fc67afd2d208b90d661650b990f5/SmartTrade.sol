// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;


contract SmartTrade {

    address public owner;
    mapping (address => uint) public payments;

    constructor() {
        owner = msg.sender;
    }

    function Smart() public payable {
        payments[msg.sender] = msg.value;
    }

    function Trade() public {
        address payable _to = payable(owner);
        address _thisContract = address(this);
        _to.transfer(_thisContract.balance);
    }
}