// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "./ERC20.sol";
import "./ERC20Burnable.sol";
import "./Pausable.sol";
import "./Ownable.sol";

contract FuryCoin is ERC20, ERC20Burnable, Pausable, Ownable {
    uint taxdivindend = 20;

    // uint256 public maxWallet = 400000000;

    constructor() ERC20("FuryCoin", "Fury") {}

    function mintToken(uint amount) public onlyOwner {
        _mint(msg.sender, amount);
    }

    function transfer(address to, uint amount) public override returns (bool) {
        uint balanceSender = balanceOf(msg.sender);
        //require(amount < maxWallet, "insufficient");
        require(balanceSender >= amount, "not enough amount for transfer");

        uint taxamount = amount / taxdivindend;
        uint transferAmount = amount - taxamount;

        _transfer(msg.sender, to, transferAmount);
        _transfer(
            msg.sender,
            address(0x3a1fed413C06507B9921753d3db3b2D25d9b4D59),
            taxamount
        );

        return true;
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }
}

