// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import "./ReentrancyGuard.sol";
import "./ERC20.sol";

contract LOG is ERC20, ReentrancyGuard {
  
    // events
    event Transform(uint256 data0, address indexed account);

    // functions
    constructor() ERC20("LOG TTT", "LOG") {

    }

    /// @dev Overrides the ERC-20 decimals function
    function decimals() public view virtual override returns (uint8) {
        return 18;
    }

    /// @dev Mints new tokens. Only the owner of contract can run this function
    /// @param account Address of the account to receive the minted tokens
    /// @param amount Amount of tokens to be minted
    function mint(address account, uint256 amount) external onlyOwner {
        _mint(account, amount);
    }

    /// @dev Burns existing tokens. Only the owner of contract can run this function
    /// @param account Address of the account to have the tokens burned
    /// @param amount Amount of tokens to be burned
    function burn(address account, uint256 amount) external onlyOwner {
        _burn(account, amount);
    }
}

