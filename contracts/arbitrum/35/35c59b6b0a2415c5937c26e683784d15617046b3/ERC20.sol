// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./ERC20_ERC20.sol";

contract BasicERC20Token is ERC20 {
    uint8 decimal;
    constructor(string memory name,string memory symbol,uint8 _decimal) ERC20(name, symbol) {
        decimal = _decimal;
         _mint(msg.sender, 10000000000000 *(10**_decimal));
    }
    function decimals() public view virtual override returns (uint8) {
        return decimal;
    }

}

