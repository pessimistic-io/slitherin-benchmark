// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.0;

import "./tokens_ERC20.sol";

contract MockWETH is ERC20{
    constructor() ERC20("XXX", "XXX"){
        _mint(msg.sender,1000*10**18);
    }
}

