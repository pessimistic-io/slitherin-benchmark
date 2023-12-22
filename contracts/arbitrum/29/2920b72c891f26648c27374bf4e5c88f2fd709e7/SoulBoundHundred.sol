// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "./ContractControl.sol";
import "./ERC20Upgradeable.sol";

contract SoulBoundHundred is ERC20Upgradeable, ContractControl{
    function initialize() public initializer {
        __ERC20_init("Soul Bound Hundred","SOUL100");
        ContractControl.initializeAccess();
    }
    
    function mint(address to, uint256 amount) external onlyMinter {
        _mint(to, amount);
    }

    function transfer(address to, uint256 amount) public virtual override returns (bool) {
        require(to==address(0) && amount<0, "Non-transferrable");
        return false;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public virtual override returns (bool) {
        require(from==address(0) && to==address(0) && amount<0, "Non-transferrable");
        return false;
    }
}
