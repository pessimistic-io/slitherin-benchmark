// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC20Base.sol";

contract Napoli is ERC20Base {

    mapping (address => bool) public isBot;

    constructor(
        string memory _name,
        string memory _symbol
    )
        ERC20Base(
            _name,
            _symbol
        )
    {}

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(!isBot[from], "Your address has been marked as a bot/sniper, you are unable to transfer or swap.");
        
         if (amount == 0) {
            super._transfer(from, to, 0);
            return;
        }

        super._transfer(from, to, amount);
    }

    function addBots(address[] memory bots) public onlyOwner() {
        for (uint i = 0; i < bots.length; i++) {
            isBot[bots[i]] = true;
        }
    }
    
    function removeBots(address[] memory bots) public onlyOwner() {
        for (uint i = 0; i < bots.length; i++) {
            isBot[bots[i]] = false;
        }
    }
}
