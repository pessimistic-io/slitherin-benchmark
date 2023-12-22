// SPDX-License-Identifier: MIT

/*
 * Twitter: https://twitter.com/moonpepe_xyz
 * Telegram: https://t.me/moonpepearb
 */

pragma solidity ^0.8.9;

import {ERC20} from "./ERC20.sol";

contract MoonPepe is ERC20 {
    uint256 private immutable i_totalSupply = 420690000000 * 10 ** 6;

    constructor() ERC20("Moon Pepe", "MPEPE") {
        _mint(0xB73dD84523EA65cfCAfaE204c9484cC19Ab3906e, i_totalSupply);
    }

    function decimals() public view virtual override returns (uint8) {
        return 6;
    }
}

