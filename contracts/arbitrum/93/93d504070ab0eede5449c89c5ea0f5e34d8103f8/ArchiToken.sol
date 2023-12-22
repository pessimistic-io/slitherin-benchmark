// SPDX-License-Identifier: MIT

pragma solidity =0.8.4;

import { ERC20 } from "./ERC20.sol";
import { IERC20 } from "./IERC20.sol";

contract ArchiToken is IERC20, ERC20 {
    constructor(uint256 totalSupply, address account) ERC20("Archi token", "ARCHI") {
        _mint(account, totalSupply);
    }
}

