// contracts/GLDToken.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC20_ERC20.sol";

contract Arbitrum is ERC20 {
    constructor(uint256 initialSupply) ERC20("Arbitrum", "ARB") {
        _mint(msg.sender, initialSupply);
    }
}
