// SPDX-License-Identifier: None
pragma solidity ^0.8.0;

import "./ERC20.sol";

contract ARV is ERC20WithSupply {
    string public constant symbol = "ARV";
    string public constant name = "ARV";
    uint8 public constant decimals = 18;

    constructor() {
        _mint(msg.sender, 1e5 ether);
    }

    function burnFrom(address from, uint256 amount) public {
        if (from != msg.sender) {
            uint256 spenderAllowance = allowance[from][msg.sender];
            // If allowance is infinite, don't decrease it to save on gas (breaks with EIP-20).
            if (spenderAllowance != type(uint256).max) {
                require(spenderAllowance >= amount, "ERC20: allowance too low");
                allowance[from][msg.sender] = spenderAllowance - amount; // Underflow is checked
            }
        }
        _burn(from, amount);
    }

    //TODO：burn logic
}

