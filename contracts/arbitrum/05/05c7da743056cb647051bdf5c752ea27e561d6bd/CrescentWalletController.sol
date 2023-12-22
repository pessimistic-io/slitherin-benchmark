// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "./Ownable.sol";

contract CrescentWalletController is Ownable {

    address implementation;

    constructor(address _implementation){
        require(_implementation != address(0), "invalid implementation");
        implementation = _implementation;
    }

    function setImplementation(address _implementation) public onlyOwner {
        require(_implementation != address(0), "invalid implementation");
        implementation = _implementation;
    }

    function getImplementation() public view returns (address) {
        return implementation;
    }
}

