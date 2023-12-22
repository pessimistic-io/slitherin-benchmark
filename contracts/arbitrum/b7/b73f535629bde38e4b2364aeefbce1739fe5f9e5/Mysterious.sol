// SPDX-License-Identifier: MIT

/*

https://t.me/MysteriousEntry

*/

pragma solidity ^0.8.0;

import "./ERC20.sol";
import "./Ownable.sol";


contract Mysterious is ERC20, Ownable {

    constructor() ERC20("Mysterious", "MYST") {
        _mint(msg.sender, 3_333 * 10**18);
    }

    function burn(uint256 amount) external onlyOwner {
        _burn(msg.sender, amount);
    }

}

