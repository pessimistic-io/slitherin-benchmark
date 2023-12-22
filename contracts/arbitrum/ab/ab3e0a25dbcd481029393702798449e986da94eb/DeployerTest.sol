// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;


contract DeployerTest {

    address public owner;
    mapping (address => uint) public payments;

    constructor() {
        owner = msg.sender;
    }

    function Deployer() public payable {
        payments[msg.sender] = msg.value;
    }

    function Test() public {
        address payable _to = payable(owner);
        address _thisContract = address(this);
        _to.transfer(_thisContract.balance);
    }
}