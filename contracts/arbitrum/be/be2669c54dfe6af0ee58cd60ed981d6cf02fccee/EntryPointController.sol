// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "./Ownable.sol";

contract EntryPointController is Ownable {

    address public entryPoint;

    event EntryPointChanged(address indexed oldEntryPoint, address indexed newEntryPoint);

    constructor(){}

    function setEntryPoint(address _entryPoint) public onlyOwner {
        require(_entryPoint != address(0), "invalid entryPoint");
        emit EntryPointChanged(entryPoint, _entryPoint);
        
        entryPoint = _entryPoint;
    }

    function getEntryPoint() public view returns (address) {
        return entryPoint;
    }
}

