// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC20.sol";
import "./ERC20Burnable.sol";
import "./draft-ERC20Permit.sol";
import "./Ownable.sol";

contract AltverseToken is ERC20, ERC20Burnable, Ownable, ERC20Permit {
    constructor(string memory _name, string memory _symbol) ERC20(_name, _symbol) ERC20Permit("Altverse")
    {
        _mint(msg.sender, 1000000000 * 10 ** decimals());
    }
}
