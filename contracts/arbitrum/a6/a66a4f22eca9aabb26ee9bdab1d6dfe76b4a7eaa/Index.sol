// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC20.sol";

contract MintableToken is ERC20 {
    address admin;

    constructor() ERC20('Vision BTC-ETH-BNB', 'IBEB') public {
        //_mint(msg.sender, 1000000 * 10**18);
        admin = msg.sender;
    }

    // function mint(uint amount) public {
    //     _mint(msg.sender, amount * 10**18);
    // }

}
