//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.9;

import "./ERC20.sol";
import "./Ownable.sol";

contract Frank is ERC20, Ownable {
    uint constant _initial_supply = 25000000 * (10**18);

    constructor() ERC20("Frank", "FRANK") {
        _mint(msg.sender, _initial_supply);
    }
}
