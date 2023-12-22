//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.17;

import "./ERC20.sol";
import "./console.sol";

/// @dev this is a dummy ERC20 token for testing purposes
contract SpindlToken is ERC20 {
    /// @dev by default, there are 18 decimal
    constructor() ERC20("Demo Coin", "DC") {}

    /// @dev method to give dummy ERC20 tokens to specific test addresses so we can test functionality
    function mintToAccount(address account, uint256 amount) external {
        _mint(account, amount);
    }
}

