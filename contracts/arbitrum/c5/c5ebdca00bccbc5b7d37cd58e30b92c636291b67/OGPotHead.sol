// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./ERC20.sol";

contract ItsOver is ERC20 {
    constructor() ERC20("Its Over", "IO", 18) {
        uint256 supply = 442_000_000_000 * 1e18;

        // deployer - 80% for lp
        _mint(msg.sender, supply);
    }
}

