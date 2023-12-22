// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./ERC20.sol";
import "./Ownable.sol";

contract BitBizToken is ERC20, Ownable {
    constructor(address initialOwner) ERC20("BitBizToken", "BTBZ") Ownable(initialOwner) {
        _mint(msg.sender, 25000000 * 10 ** decimals());
    }

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }
}
