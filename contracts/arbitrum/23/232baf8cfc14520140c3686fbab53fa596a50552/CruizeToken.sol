// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./Ownable.sol";
import "./ERC20.sol";
import "./ERC20Burnable.sol";
import "./draft-ERC20Permit.sol";

contract CruizeToken is ERC20, ERC20Burnable, Ownable, ERC20Permit
{
    
    constructor(address account) ERC20("Cruize", "CRUIZE") ERC20Permit("Cruize") {
        _mint(account, 100000000 * 1e18);
    }

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }
}
