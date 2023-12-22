// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.6.12;

import "./Zap.sol";

contract ZapFactory {
    event NewZap(address indexed owner, address indexed zap);

    mapping(address => address) public zaps;

    function create() public returns (address newZap) {
        require(zaps[msg.sender] == address(0), "ZapFactory: zap exists");
        Zap zap = new Zap(msg.sender);

        zaps[msg.sender] = address(zap);
        emit NewZap(msg.sender, address(zap));
        return address(zap);
    }
}

