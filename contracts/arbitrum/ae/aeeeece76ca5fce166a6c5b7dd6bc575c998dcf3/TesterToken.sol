// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./ERC20.sol";
import "./ERC20Burnable.sol";
import "./Ownable.sol";

contract TesterToken is ERC20, ERC20Burnable, Ownable{
    constructor() ERC20("TesterToken", "TT") {
        _mint(msg.sender, 1000000 * 10 ** 18);
    }
}
