// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.4;

import "./Address.sol";
import "./ERC20.sol";

contract USDC is ERC20("USDC", "USDC") {
    constructor() {
        uint256 INITIAL_SUPPLY = 1000 * 10 ** 6 * 10 ** decimals();
        _mint(msg.sender, INITIAL_SUPPLY);
    }

    function decimals() public view virtual override returns (uint8) {
        return 6;
    }
}

