// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./ERC20.sol";

contract HarvestToken is ERC20 {
    constructor() ERC20("Harvest Token", "HRVST") {
        _mint(msg.sender, 10_000_000 * 10 ** decimals());
    }

    function burn(uint256 amount) public {
        _burn(_msgSender(), amount);
    }
}

