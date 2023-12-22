// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC20.sol";
import "./Ownable.sol";

contract StanderERC20 is ERC20, Ownable {
    constructor(
        string memory shortname,
        string memory name,
        uint256 initialSupply
    ) ERC20(shortname, name) {
        _mint(msg.sender, initialSupply);
    }

    function decimals() public view virtual override returns (uint8) {
        return 18;
    }
}

