// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import { ERC20Upgradeable } from "./ERC20Upgradeable.sol";

contract MockToken is ERC20Upgradeable {
    function initialize() external initializer {
        __ERC20_init("Mock Token", "MCK");
    }

    function mint(uint256 _amount) external {
        _mint(msg.sender, _amount);
    }

    function burn(uint256 _amount) external {
        _burn(msg.sender, _amount);
    }
}

