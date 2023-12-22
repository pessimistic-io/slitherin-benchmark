// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./ERC20.sol";
import "./Ownable.sol";

contract RKT is ERC20, Ownable {
    constructor() ERC20("RKT Token", "RKT") {
        _mint(msg.sender, 1000000000 * 10**decimals());
    }

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }
}

