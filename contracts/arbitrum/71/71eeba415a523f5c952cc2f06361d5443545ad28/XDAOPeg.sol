/*
██   ██ ██████   █████   ██████      ████████  ██████  ██   ██ ███████ ███    ██ 
 ██ ██  ██   ██ ██   ██ ██    ██        ██    ██    ██ ██  ██  ██      ████   ██ 
  ███   ██   ██ ███████ ██    ██        ██    ██    ██ █████   █████   ██ ██  ██ 
 ██ ██  ██   ██ ██   ██ ██    ██        ██    ██    ██ ██  ██  ██      ██  ██ ██ 
██   ██ ██████  ██   ██  ██████         ██     ██████  ██   ██ ███████ ██   ████ 
*/
// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.6;

import "./ERC20.sol";
import "./ERC20Burnable.sol";
import "./Ownable.sol";
import "./draft-ERC20Permit.sol";

contract XDAOPeg is ERC20, ERC20Burnable, Ownable, ERC20Permit {
    constructor() ERC20("XDAO", "XDAO") ERC20Permit("XDAO") {}

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }
}

