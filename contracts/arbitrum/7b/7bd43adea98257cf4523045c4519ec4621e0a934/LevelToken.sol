// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.18;

import {ERC20Burnable} from "./ERC20Burnable.sol";
import {ERC20} from "./ERC20.sol";

contract LevelToken is ERC20Burnable {
    uint256 public constant MAX_SUPPLY = 50_000_000 ether;

    constructor() ERC20("Not Level Token", "nLVL") {
        _mint(_msgSender(), MAX_SUPPLY);
    }
}

