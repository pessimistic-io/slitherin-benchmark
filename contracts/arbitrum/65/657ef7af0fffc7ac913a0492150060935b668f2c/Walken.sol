//SPDX-License-Identifier: MIT
pragma solidity =0.8.18;

/**
 * @title Walken
 * @author gotbit
 */

import "./ERC20.sol";

contract Walken is ERC20 {
    constructor() ERC20('Walken', 'WLKN') {
        _mint(msg.sender, 2_000_000_000 ether);
    }
}

