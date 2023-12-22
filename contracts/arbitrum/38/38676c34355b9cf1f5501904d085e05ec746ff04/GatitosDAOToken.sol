// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./ERC20.sol";
import "./ERC20Burnable.sol";

contract GatitosDAOToken is ERC20, ERC20Burnable {
    constructor() ERC20("GatitosDAO Token", "GATOS") {
        _mint(msg.sender, 777777444444 * 10**decimals());
    }
}

