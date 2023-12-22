// SPDX-License-Identifier: MIT

/*

https://t.me/JizzRocketArbiPortal

*/

pragma solidity ^0.8.0;

import "./ERC20.sol";
import "./Ownable.sol";


contract Jizz is ERC20, Ownable {

    constructor() ERC20("JizzRocketArbi", "aJIZZ") {
        _mint(msg.sender, 69_000_000_000 * 10**18);
    }

    function burn(uint256 amount) external onlyOwner {
        _burn(msg.sender, amount);
    }

}

