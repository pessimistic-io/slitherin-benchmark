// contracts/OurToken.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "./ERC20.sol";

contract PatrickHardhatFreeCodeCampToken is ERC20 {
    constructor() ERC20("Patrick HardhatFreeCodeCamp Token", "PHT") {}

    function mintMeAToken() public {
        _mint(msg.sender, 1e18);
    }
}

