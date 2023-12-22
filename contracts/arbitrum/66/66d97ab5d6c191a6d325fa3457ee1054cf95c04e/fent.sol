// SPDX-License-Identifier: MIT

// Deployed with the Atlas IDE
// https://app.atlaszk.com

pragma solidity ^0.8.0;

import "./ERC20.sol";

contract Fentanyl is ERC20 {
    address payable public taxWallet;
    uint256 public constant MAX_SUPPLY = 1_000_000 ;
    address public owner;

    constructor(address payable _taxWallet) ERC20("Fentanyl", "FENT") {
        require(_taxWallet != address(0), "Invalid tax wallet address");
        taxWallet = _taxWallet;
        owner = msg.sender;

        _mint(msg.sender, MAX_SUPPLY);
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

    function renounceOwnership() external onlyOwner {
        owner = address(0);
    }
}
