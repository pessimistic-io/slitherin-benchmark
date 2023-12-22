// SPDX-License-Identifier: AGPL-3.0-or-later

/*

https://t.me/arb_income
https://twitter.com/Arbincome

Passive Income

*/

pragma solidity ^0.8.13;

import "./ERC20.sol";
import "./Ownable.sol";

contract ArbIncome is ERC20, Ownable {

    constructor() ERC20("ARBINCOME", "ARBIN") {
        _mint(msg.sender, 100000 * 10**18);
    }

}
