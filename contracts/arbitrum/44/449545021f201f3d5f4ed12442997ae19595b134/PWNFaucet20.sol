// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {ERC20} from "./ERC20.sol";


contract PWNFaucet20 is ERC20 {

    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {}


    function mint(address receiver, uint256 amount) external {
        _mint(receiver, amount);
    }

}

