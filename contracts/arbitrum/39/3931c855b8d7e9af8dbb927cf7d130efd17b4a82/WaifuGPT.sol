//SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./ERC20.sol";
import "./ERC20Burnable.sol";
import "./TokenWithdrawable.sol";

contract WaifuGPT is ERC20, ERC20Burnable, TokenWithdrawable {
    constructor() ERC20("WaifuGPT", "WGPT") {
        _mint(msg.sender, 1e27);
    }
}
