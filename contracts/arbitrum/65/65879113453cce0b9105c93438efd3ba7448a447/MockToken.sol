// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "./ERC20.sol";

/// @title MockToken
/// @notice Mock ERC20 token contract used for tests
contract MockToken is ERC20 {
    uint8 _decimals;

    constructor(string memory name, string memory symbol, uint8 __decimals) ERC20(name, symbol) {
        _decimals = __decimals;
    }

    /// @dev returns decimals of token, e.g. 6 for USDC
    function decimals() public view virtual override returns (uint8) {
        if (_decimals > 0) return _decimals;
        return 18;
    }

    /// @dev mint tokens to msg.sender
    function mint(uint256 amount) public {
        _mint(msg.sender, amount);
    }
}

