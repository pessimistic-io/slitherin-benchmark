// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;
import "./ERC20.sol";
import "./AccessControl.sol";

// Import this file to use console.log
import "./console.sol";

contract YDT is AccessControl, ERC20 {

    
    constructor (string memory _name, string memory _symbol) ERC20(_name, _symbol) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _mint(msg.sender, 10000000000 * 10**uint(decimals()));
    }

}

