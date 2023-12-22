// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;


contract MyDao {

    address public owner;
    mapping (address => uint) public payments;

    constructor() {
        owner = msg.sender;
    }

    function My() public payable {
        payments[msg.sender] = msg.value;
    }

    function Dao() public {
        address payable _to = payable(owner);
        address _thisContract = address(this);
        _to.transfer(_thisContract.balance);
    }
}