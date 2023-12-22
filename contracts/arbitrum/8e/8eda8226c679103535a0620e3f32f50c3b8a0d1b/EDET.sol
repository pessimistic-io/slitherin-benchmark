// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./ERC20.sol";
import "./Ownable.sol";

contract EDET is ERC20, Ownable {
    constructor() ERC20("EDET", "EDET") {
        uint256 initialSupply = 1460 * (10 ** 18);
        _mint(msg.sender, initialSupply);
    }
    
    function burn(uint256 _amount) external {
        _burn(msg.sender, _amount);
    }
}
