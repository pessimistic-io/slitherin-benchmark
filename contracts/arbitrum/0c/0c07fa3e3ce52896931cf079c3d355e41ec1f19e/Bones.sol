// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "./ContractControl.sol";
import "./ERC20Upgradeable.sol";

contract Bones is ERC20Upgradeable, ContractControl{
    function initialize() public initializer {
        __ERC20_init("Bones","BONES");
        ContractControl.initializeAccess();
     }

    function mint(address to, uint256 amount) external onlyMinter {
        _mint(to, amount);
    }
}
