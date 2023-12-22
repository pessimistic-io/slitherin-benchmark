// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./ERC20.sol";
import "./Ownable.sol";

contract EDE is ERC20, Ownable {
    constructor() ERC20("EDE", "EDE") {
        uint256 initialSupply = 15150000 * (10 ** 18);
        _mint(msg.sender, initialSupply);
    }
    
    function burn(uint256 _amount) external {
        _burn(msg.sender, _amount);
    }
}
