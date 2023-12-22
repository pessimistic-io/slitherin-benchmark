// contracts/GLDToken.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./ERC20.sol";

contract SniperToken is ERC20
{
    constructor() ERC20(unicode"DoNotApeThisShit", "Shit")
    {
        _mint(msg.sender, 1_000_000 * 10 ** 18);
    }
}

