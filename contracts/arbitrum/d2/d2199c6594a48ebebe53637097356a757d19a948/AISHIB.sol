// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC20.sol";
/**
 * @dev AI SHIB , HAVE FUN
 */
contract AISHIB is ERC20 {


    constructor() ERC20("AISHIB", "AISHIB") {
        _mint(msg.sender, 7_777_777_777_777_777 * 1E18);
    }
    
    
}

