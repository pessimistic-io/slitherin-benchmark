// SPDX-License-Identifier: MIT
pragma solidity =0.8.15;

import {Ownable} from "./access_Ownable.sol";
import "./ERC20_ERC20.sol";

contract MockToken is ERC20, Ownable {
    constructor(
        string memory name_,
        string memory symbol_
    ) ERC20(name_, symbol_) {
        _mint(msg.sender, 1000000e18);
    }
}

