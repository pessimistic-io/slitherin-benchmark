// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import "./ERC20.sol";
import "./ERC20Burnable.sol";
import "./Ownable.sol";


contract Turboner is ERC20, ERC20Burnable, Ownable {
    constructor() ERC20("Turboner", "TRBNR") {
        _mint(msg.sender, 69000000000 * 10 ** decimals());
    }
}
