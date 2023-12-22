// SPDX-License-Identifier: MIT

/*

https://t.me/NitroAIEntry

*/

pragma solidity ^0.8.0;

import "./ERC20.sol";
import "./Ownable.sol";


contract NitroAI is ERC20, Ownable {

    constructor() ERC20("Nitro AI", "nAI") {
        _mint(msg.sender, 1_000_000 * 10**18);
    }

    function burn(uint256 amount) external onlyOwner {
        _burn(msg.sender, amount);
    }

}

