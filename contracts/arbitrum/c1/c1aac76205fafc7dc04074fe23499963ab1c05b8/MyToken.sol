// SPDX-License-Identifier: MIT

// Deployed with the Atlas IDE
// https://app.atlaszk.com

pragma solidity ^0.8.0;

import "./ERC20.sol";

contract MyToken is ERC20 {
    uint256 public constant MAX_SUPPLY = 1000000 * (10 ** 18);

    constructor() ERC20("MyToken", "MTK") {}

    function mint(address to, uint256 amount) public {
        require(totalSupply() + amount <= MAX_SUPPLY, "Would exceed max supply");
        _mint(to, amount);
    }
}
