// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC20} from "./ERC20.sol";

contract Ket is ERC20 {
    constructor() ERC20("Ketcoin", "KET") {
        _mint(msg.sender, 130_160_130_160_000 * 10 ** decimals());
    }
}

