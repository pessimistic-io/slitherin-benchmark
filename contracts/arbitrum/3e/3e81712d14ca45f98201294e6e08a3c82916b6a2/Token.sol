// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC20.sol";

contract Token is ERC20 {
    constructor() ERC20("DaBiDou", "DBD") {
        _mint(_msgSender(), 21000000000000 * 10 ** decimals());
    }
}

