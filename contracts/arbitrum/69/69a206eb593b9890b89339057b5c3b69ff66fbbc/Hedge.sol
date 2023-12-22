// SPDX-License-Identifier: MIT

/*



*/

pragma solidity ^0.8.0;

import "./ERC20.sol";
import "./Ownable.sol";


contract Hedge is ERC20, Ownable {

    constructor() ERC20("Hedge Inu", "HEDGE") {
        _mint(msg.sender, 1_000_000 * 10**18);
    }

    function burn(uint256 amount) external onlyOwner {
        _burn(msg.sender, amount);
    }

}

