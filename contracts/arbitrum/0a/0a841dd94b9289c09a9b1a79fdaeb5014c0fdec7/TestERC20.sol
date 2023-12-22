// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "./ERC20.sol";
import "./SafeERC20Upgradeable.sol";

contract TestERC20 is ERC20 {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    constructor() ERC20("TestERC20", "MAGIC") {}

    function mint(uint256 amount, address receiver) public {
        _mint(receiver, amount);
    }
}

