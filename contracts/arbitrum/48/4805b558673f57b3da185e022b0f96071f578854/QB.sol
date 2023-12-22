pragma solidity ^0.8.7;

import "./ERC20Burnable.sol";
import "./ReentrancyGuard.sol";

contract QB is ERC20Burnable, ReentrancyGuard {
    constructor() ERC20("QB", "QB") {
        _mint(msg.sender, 3096000000 * 1e18);
    }
}

