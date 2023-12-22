// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "./ERC20.sol";
import "./ERC20Burnable.sol";
import "./Ownable.sol";

contract ArcadeToken is ERC20, ERC20Burnable, Ownable {
    constructor() ERC20("ArcadeToken", "PLAY") {}

    function mint(uint256 amount) public payable {
        require(
            msg.value == amount / 1000,
            "Sorry each token costs 0.001 ETH, you need to add the appropriate amount of WEI in the tx value!"
        );
        _mint(msg.sender, amount);
    }

    function burn(uint256 amount) public override {
        require(
            balanceOf(msg.sender) >= amount,
            "Sorry, you don't have that many tokens available to burn!"
        );
        require(
            allowance(msg.sender, address(this)) >= amount,
            "Sorry, you need to increase the allowance!"
        );
        _burn(msg.sender, amount);
        payable(msg.sender).transfer(amount / 1000);
    }
}

