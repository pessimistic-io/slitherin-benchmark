// SPDX-License-Identifier: MIT

// Deployed with the Atlas IDE
// https://app.atlaszk.com

pragma solidity ^0.8.0;

import "./ERC20.sol";

contract Dickhead is ERC20 {
    address payable public taxWallet;
    uint256 public constant MAX_SUPPLY = 10_000_000 * 10**18;
    uint256 public constant MINT_PRICE = 10_000_000_000; // 0.00001 ETH for 1000 tokens
    address public owner;

    constructor(address payable _taxWallet) ERC20("Dickhead", "DICKHEAD") {
        require(_taxWallet != address(0), "Invalid tax wallet address");
        taxWallet = _taxWallet;
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Caller is not the owner");
        _;
    }

    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal override {
        uint256 taxAmount = (amount * 2) / 100;
        uint256 netAmount = amount - taxAmount;

        super._transfer(sender, taxWallet, taxAmount);
        super._transfer(sender, recipient, netAmount);
    }

    function mint() external payable {
        uint256 amount = msg.value / MINT_PRICE;
        require(totalSupply() + amount <= MAX_SUPPLY, "Max supply exceeded");
        require(msg.value >= MINT_PRICE, "Minimum ETH value not sent");

        _mint(msg.sender, amount);
        taxWallet.transfer(msg.value);
    }

    function renounceOwnership() external onlyOwner {
        owner = address(0);
    }
}
