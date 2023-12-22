// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./ERC20.sol";
import "./Ownable.sol";

contract RKT6 is ERC20, Ownable {
    constructor() ERC20("RKT6 Token", "RKT6") {
        _mint(msg.sender, 1000000000 * 10 ** decimals());
    }

    function decimals() public view virtual override returns (uint8) {
        return 6;
    }

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }
}

