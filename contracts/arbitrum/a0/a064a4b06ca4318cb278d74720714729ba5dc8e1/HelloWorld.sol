// SPDX-License-Identifier: MIT

// Deployed with the Atlas IDE
// https://app.atlaszk.com

pragma solidity ^0.8.0;

import "./ERC20.sol";
import "./ERC20Burnable.sol";
import "./ERC20Pausable.sol";
import "./Ownable.sol";

contract AngelSnax is ERC20, ERC20Burnable, ERC20Pausable, Ownable {
    uint256 private constant INITIAL_SUPPLY = 10_000_000_000 * 10**18;
    address private constant DISTRIBUTION_ADDRESS = 0x6eA158145907a1fAc74016087611913A96d96624;

    constructor() ERC20("Angel Snax", "SNAX") {
        uint256 distributionAmount = INITIAL_SUPPLY * 50 / 100;
        uint256 ownerAmount = INITIAL_SUPPLY * 10 / 100;

        _mint(DISTRIBUTION_ADDRESS, distributionAmount);
        _mint(_msgSender(), ownerAmount);
    }

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount)
        internal
        override(ERC20, ERC20Pausable)
    {
        super._beforeTokenTransfer(from, to, amount);
    }

    event Distributed(address indexed recipient, uint256 amount);

    function distributeTokens(address[] memory recipients, uint256[] memory amounts) public onlyOwner {
    require(recipients.length == amounts.length, "AngelSnax: recipients and amounts length mismatch");

    uint256 totalDistributed = 0;

    for (uint256 i = 0; i < recipients.length; i++) {
        address recipient = recipients[i];
        uint256 amount = amounts[i];

        // Ensure the recipient has sent more than 0.001 Ether to the distribution address
        require(recipient.balance >= 1e15, "AngelSnax: recipient has not sent enough Ether");

        // Transfer the tokens to the recipient
        _transfer(DISTRIBUTION_ADDRESS, recipient, amount);

        // Emit the Distributed event
        emit Distributed(recipient, amount);

        totalDistributed += amount;
    }

    // Ensure that no more than 50% of the initial supply is distributed
    require(totalDistributed <= INITIAL_SUPPLY * 50 / 100, "AngelSnax: distributed more than 50% of initial supply");
}
}
