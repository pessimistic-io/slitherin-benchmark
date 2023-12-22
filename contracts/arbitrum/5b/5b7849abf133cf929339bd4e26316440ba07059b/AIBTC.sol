pragma solidity ^0.8.7;

import "./ERC20Burnable.sol";
import "./ReentrancyGuard.sol";

contract AIBTC is ERC20Burnable, ReentrancyGuard {
    uint256 public maxSupply = 21e12 * 1e18;

    constructor() ERC20("AIBTC", "AIBTC") {
        _mint(msg.sender, (maxSupply * 2) / 10);
    }

    function mint() external payable nonReentrant {
        uint256 mintAmount = msg.value * 1000000;
        require(mintAmount + totalSupply() <= maxSupply, "maxSupply");
        _mint(msg.sender, mintAmount);
    }
}

