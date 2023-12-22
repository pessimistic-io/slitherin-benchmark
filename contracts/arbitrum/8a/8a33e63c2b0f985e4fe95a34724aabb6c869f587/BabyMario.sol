// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "./ERC20.sol";

contract BabyMario is ERC20 {

    constructor() ERC20("Baby Mario", "BABYMARIO") {
        _mint(msg.sender, 100000000000 * 10 ** decimals());
    }
    
}

