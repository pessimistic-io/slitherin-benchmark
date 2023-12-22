// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./ERC20.sol";


contract LP_ETH_ZOO is ERC20 {
    constructor(uint amount) ERC20("Liquidity Pool ETH/ZOO", "LP-ETH/ZOO") {
        mint(amount);
    }

    function mint(uint256 amount) public {
        _mint(msg.sender, amount);
    }
}

