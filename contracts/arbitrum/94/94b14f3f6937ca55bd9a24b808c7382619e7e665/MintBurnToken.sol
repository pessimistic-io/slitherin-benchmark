// SPDX-License-Identifier: MIT
pragma solidity =0.8.19;

import "./ERC20.sol";
import "./ERC20Burnable.sol";
import "./Ownable.sol";
import "./ERC20Permit.sol";

contract PortalEnergyToken is ERC20, ERC20Burnable, Ownable, ERC20Permit {
    constructor(
        address initialOwner,
        string memory name,
        string memory symbol
    ) ERC20(name, symbol) Ownable(initialOwner) ERC20Permit(name) {}

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }
}
