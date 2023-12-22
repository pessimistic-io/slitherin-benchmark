// SPDX-License-Identifier: MIT

pragma solidity ^0.7.5;

contract Ownable {

    address public owner;

    constructor () {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require( owner == msg.sender, "Ownable: caller is not the owner" );
        _;
    }
    
    function transferOwnership(address _newOwner) external onlyOwner() {
        require( _newOwner != address(0) );
        owner = _newOwner;
    }
}
