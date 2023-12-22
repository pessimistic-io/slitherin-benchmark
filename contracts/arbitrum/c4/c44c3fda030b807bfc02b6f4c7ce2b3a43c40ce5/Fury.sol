// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "./ERC20.sol";
import "./ERC20Burnable.sol";
import "./Pausable.sol";
import "./Ownable.sol";

contract Fury is ERC20, ERC20Burnable, Pausable, Ownable {
    uint taxdivindend = 20;

    // uint256 public maxWallet = 400000000;

    constructor() ERC20("Arb Fury", "$Fury") {}

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
            address(0xCCC67EEDfdec07dF0C79CF7AEf621574f3a704BB),
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

