// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;
import { ERC20 } from "./ERC20.sol";

contract MockERC20 is ERC20 {
    constructor() ERC20("MockERC20", "MCK20") {
        uint256 supply = 1_000_000 * (10 ** decimals());
        _mint(msg.sender, supply);
    }
}

