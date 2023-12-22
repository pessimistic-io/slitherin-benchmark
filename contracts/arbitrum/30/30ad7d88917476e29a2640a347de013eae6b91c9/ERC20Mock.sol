// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./ERC20.sol";
import "./Ownable.sol";

contract ERC20Mock is ERC20, Ownable {
    constructor(
        string memory name,
        string memory symbol,
        uint256 supply
    ) public ERC20(name, symbol) {
        _mint(msg.sender, supply);
    }
}

