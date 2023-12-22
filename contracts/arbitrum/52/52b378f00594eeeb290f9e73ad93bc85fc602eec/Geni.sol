// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "./ERC20.sol";
import "./ERC20Burnable.sol";
import "./Ownable.sol";

contract Geni is ERC20, ERC20Burnable, Ownable {
    uint256 public constant MAX_SUPPLY = 10000000 * 10 ** 18; // 10M GENI

    constructor() ERC20("GENI TEST", "GeniBot TEST") {}

    function mint(address to, uint256 amount) public onlyOwner {
        uint256 currentSupply = totalSupply();
        require(currentSupply + amount <= MAX_SUPPLY, "Exceeds maximum total supply");
        _mint(to, amount);
    }
}

