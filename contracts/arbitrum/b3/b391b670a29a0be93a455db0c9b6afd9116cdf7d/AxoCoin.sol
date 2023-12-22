// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC20.sol";
import "./Ownable.sol";

contract AxoCoin is ERC20, Ownable {
    uint256 private totalsupply = 1000000000 * 10 ** decimals();

    constructor() ERC20("AXOCOIN", "AXOCOIN") {
        _mint(msg.sender, totalsupply);
    }

    function burn(uint amount) external {
        _burn(msg.sender, amount);
    }
}

