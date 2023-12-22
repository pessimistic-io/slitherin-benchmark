//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "./Ownable.sol";
import "./ERC20.sol";

contract ProyecX is ERC20, Ownable {

    constructor() ERC20("Project X", "PRX") {
        _mint(msg.sender, 200000 * 1e18);
    }
}

