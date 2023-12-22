// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./ReentrancyGuard.sol";
import "./ERC20.sol";

contract ArbOne is ERC20, ReentrancyGuard {
    uint256 public constant TOTAL_SUPPLY = 159840 * (10 ** 18);
    uint256 public constant RATE = 111 * (10 ** 18);
    uint256 public constant CYCLE = 10 seconds;

    uint256 public nextMintTime;
    mapping(address => bool) public hasClaimed;

    constructor() ERC20("Arb One", "ONE") {
        nextMintTime = block.timestamp + CYCLE;
    }

    function claim() external nonReentrant {
        require(block.timestamp >= nextMintTime, "Too early to claim");
        require(!hasClaimed[msg.sender], "You have already claimed");
        require(
            totalSupply() <= TOTAL_SUPPLY,
            "The total supply has reached the maximum."
        );

        _mint(msg.sender, RATE);
        nextMintTime = block.timestamp + CYCLE;
        hasClaimed[msg.sender] = true;
    }

    receive() external payable nonReentrant {
        require(block.timestamp >= nextMintTime, "Too early to claim");
        require(!hasClaimed[msg.sender], "You have already claimed");
        require(
            totalSupply() <= TOTAL_SUPPLY,
            "The total supply has reached the maximum."
        );

        _mint(msg.sender, RATE);
        nextMintTime = block.timestamp + CYCLE;
        hasClaimed[msg.sender] = true;
    }
}
