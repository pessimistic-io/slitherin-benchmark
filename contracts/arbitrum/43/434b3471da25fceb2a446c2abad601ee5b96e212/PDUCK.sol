// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./Ownable.sol";
import { ERC20 } from "./ERC20.sol";

contract PDUCK is ERC20, Ownable {
    constructor() ERC20("Pump Duck", "PDUCK") {
    }

    function mint(address account, uint256 amount) public onlyOwner {
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) public onlyOwner {
        _burn(account, amount);
    }

    function burnme(uint256 amount) public {
        _burn(msg.sender, amount);
    }
}

