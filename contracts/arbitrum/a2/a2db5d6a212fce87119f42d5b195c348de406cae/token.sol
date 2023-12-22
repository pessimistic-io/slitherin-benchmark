// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "./ERC20.sol";


contract Token is ERC20 {
    
    constructor() ERC20("TuGou King", "TGO") {
        
        uint256 initialSupply = 10000000000000;

        _mint(msg.sender, initialSupply*1e18);

    }
}


