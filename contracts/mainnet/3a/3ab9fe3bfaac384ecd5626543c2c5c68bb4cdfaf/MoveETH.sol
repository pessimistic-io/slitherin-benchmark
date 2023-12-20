//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "./console.sol";

contract MoveETH {
    function deposit() public payable {}

    function destruct(address to) public {
        address payable addr = payable(address(to));
        selfdestruct(addr);
    }
}

