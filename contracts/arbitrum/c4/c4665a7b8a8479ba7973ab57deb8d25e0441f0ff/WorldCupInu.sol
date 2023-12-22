// SPDX-License-Identifier: MIT

/*

World Cup Inu on Arbitrum

https://t.me/WorldCupInuArbitrum

*/

pragma solidity ^0.8.0;

import "./ERC20.sol";
import "./Ownable.sol";


contract WorldCupInu is ERC20, Ownable {

    constructor() ERC20("World Cup Inu Arbitrum", "aWCI") {
        _mint(msg.sender, 1_000_000 * 10**18);
    }

    function burn(uint256 amount) external onlyOwner {
        _burn(msg.sender, amount);
    }

}

