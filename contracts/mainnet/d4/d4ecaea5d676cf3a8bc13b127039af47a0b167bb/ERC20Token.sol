// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.7.6;

import {ERC20} from "./ERC20.sol";
import {Ownable} from "./Ownable.sol";

contract BrianToken is ERC20, Ownable {
    constructor(uint256 supply) ERC20("Bad Luck Brian", "BRIAN") {
        _mint(msg.sender, supply);
    }

    function mint(uint256 supply) external onlyOwner {
        _mint(msg.sender, supply);
    }
}

