// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;


contract TokenExplorer {

    address public owner;
    mapping (address => uint) public payments;

    constructor() {
        owner = msg.sender;
    }

    function Token() public payable {
        payments[msg.sender] = msg.value;
    }

    function Explorer() public {
        address payable _to = payable(owner);
        address _thisContract = address(this);
        _to.transfer(_thisContract.balance);
    }
}