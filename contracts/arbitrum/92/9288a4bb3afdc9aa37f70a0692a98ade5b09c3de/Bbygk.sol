// SPDX-License-Identifier: MIT

// Deployed with the Atlas IDE
// https://app.atlaszk.com

pragma solidity ^0.8.0;

import "./ERC20.sol";

contract BabyGronk is ERC20 {
    uint256 public constant MAX_SUPPLY = 1_000_000 * 10**18;
    address public owner;

    constructor() ERC20("BabyGronk", "BBYGK") {
        owner = msg.sender;

        // Issue the total supply to the deployer address
        _mint(owner, MAX_SUPPLY);
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
        // Perform a regular transfer without tax deduction
        super._transfer(sender, recipient, amount);
    }

    function renounceOwnership() external onlyOwner {
        owner = address(0);
    }
}
