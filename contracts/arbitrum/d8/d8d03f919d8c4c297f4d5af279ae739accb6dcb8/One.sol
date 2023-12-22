// SPDX-License-Identifier: MIT

// Deployed with the Atlas IDE
// https://app.atlaszk.com

pragma solidity ^0.8.4;

import "./ReentrancyGuard.sol";
import "./ERC20.sol";

contract One is ERC20, ReentrancyGuard {
    uint256 public constant TOTAL_SUPPLY = 10240000 * (10 ** 18);
    uint256 public constant RATE1 = 2048 * (10 ** 18);
    uint256 public constant RATE2 = 1024 * (10 ** 18);
    uint256 public constant CYCLE = 10 seconds;

    uint256 public nextMintTime;
    mapping(address => bool) public hasClaimed;

    constructor() ERC20("One", "ONE") {
        nextMintTime = block.timestamp + CYCLE;
    }

    function _mint(address account, uint256 amount) internal virtual override {
        require(account != address(0), "ERC20: mint to the zero address");
        require(totalSupply() + amount <= TOTAL_SUPPLY, "ERC20: mint amount exceeds TOTAL_SUPPLY");

        super._mint(account, amount);
    }

    function claim() external nonReentrant {
        require(block.timestamp >= nextMintTime, "Too early to claim");
        require(!hasClaimed[msg.sender], "You have already claimed");

        uint256 amount = (block.timestamp % 2 == 0) ? RATE1 : RATE2;
        _mint(msg.sender, amount);
        nextMintTime = block.timestamp + CYCLE;
        hasClaimed[msg.sender] = true;
    }

    receive() external payable nonReentrant {
        require(block.timestamp >= nextMintTime, "Too early to claim");
        require(!hasClaimed[msg.sender], "You have already claimed");

        uint256 amount = (block.timestamp % 2 == 0) ? RATE1 : RATE2;
        _mint(msg.sender, amount);
        nextMintTime = block.timestamp + CYCLE;
        hasClaimed[msg.sender] = true;
    }
}

