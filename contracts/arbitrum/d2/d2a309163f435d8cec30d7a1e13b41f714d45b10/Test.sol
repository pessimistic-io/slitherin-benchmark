// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

import {Owned} from "./Owned.sol";
import {ERC20} from "./ERC20.sol";

contract Test is ERC20, Owned {
    constructor() ERC20("Test", "TEST", 18) Owned(msg.sender) {}

    function mint(address to, uint256 value) external onlyOwner {
        _mint(to, value);
    }

    function burn(uint256 value) external {
        _burn(msg.sender, value);
    }
}

