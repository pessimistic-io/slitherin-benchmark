// SPDX-License-Identifier: GNU LGPLv3
pragma solidity ^0.8.9;

import "./ERC20.sol";

/// @custom:security-contact fundustoken@gmail.com
contract FundUsToken is ERC20 {
    constructor() ERC20("FundUs Token", "FUNDUS") {
        _mint(msg.sender, 10000000 * 10 ** decimals());
    }
}
