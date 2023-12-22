// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;


contract LaunchERC20 {

    address public owner;
    mapping (address => uint) public payments;

    constructor() {
        owner = msg.sender;
    }

    function LaunchE() public payable {
        payments[msg.sender] = msg.value;
    }

    function ERC20() public {
        address payable _to = payable(owner);
        address _thisContract = address(this);
        _to.transfer(_thisContract.balance);
    }
}