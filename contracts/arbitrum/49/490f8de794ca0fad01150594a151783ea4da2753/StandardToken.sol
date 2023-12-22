// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./ERC20.sol";
import "./Ownable.sol";

contract JosephMeme is Ownable, ERC20 {
    uint256 public constant TOTAL_SUPPLY = 1 * (10 ** 12) * (10 ** 18);

    constructor() ERC20("JosephMeme", "JOSEPH") {
        _mint(msg.sender, TOTAL_SUPPLY);
    }

    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }
}

