//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./ERC20.sol";
import "./Ownable.sol";
import "./draft-ERC20Permit.sol";

contract AssetToken is ERC20, ERC20Permit, Ownable {
    constructor(
        string memory name,
        string memory symbol
    ) ERC20(name, symbol) ERC20Permit(name) {}

    function mint(address account, uint256 amount) external onlyOwner {
        _mint(account, amount);
    }

    function burn(uint256 amount) external onlyOwner {
        _burn(msg.sender, amount);
    }
}

