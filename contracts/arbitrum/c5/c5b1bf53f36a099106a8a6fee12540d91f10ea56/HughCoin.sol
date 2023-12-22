// SPDX-License-Identifier: MIT
// Author: Hugh Pearse
pragma solidity ^0.8.20;

import {ERC20} from "./ERC20.sol";

/// @custom:security-contact hughpearse@gmail.com
contract HughCoin is ERC20 {
    address public owner;

    constructor() 
    ERC20("HughCoin", "HUGH") 
    {
        owner = msg.sender;
    }

    function deposit() public payable {
        require(msg.value > 0, "Deposit value must be greater than 0");
        _mint(msg.sender, msg.value);
    }

    function withdraw(uint256 amount) public {
        require(balanceOf(msg.sender) >= amount, "Not enough tokens to withdraw");
        _burn(msg.sender, amount);
        payable(msg.sender).transfer(amount);
    }

    receive() external payable {
        deposit();
    }
}
