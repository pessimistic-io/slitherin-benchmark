// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import "./ERC20.sol";

contract HuppieCoin is ERC20 {
    constructor() ERC20("Huppie", "HUPPIE") {
      _mint(msg.sender, 100000000000000 * 10 ** decimals());
    }
    
    function decimals() public view virtual override returns (uint8) {
        return 6;
    }
}
