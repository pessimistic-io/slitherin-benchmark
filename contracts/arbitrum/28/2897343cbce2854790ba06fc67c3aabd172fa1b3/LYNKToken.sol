// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.9;

import "./baseContract.sol";
import "./IERC20Mintable.sol";
import "./OwnableUpgradeable.sol";
import "./draft-ERC20PermitUpgradeable.sol";
// Uncomment this line to use console.log
// import "hardhat/console.sol";

contract LYNKToken is ERC20PermitUpgradeable, OwnableUpgradeable, baseContract, IERC20Mintable {

    constructor(address dbAddress) baseContract(dbAddress) { }

    function __LYNKToken_init() public initializer {
        __LYNKToken_init_unchained();
        __Ownable_init();
        __ERC20Permit_init("LYNK Token");
        __ERC20_init("LYNK Token", "LYNK");
        __baseContract_init();
    }

    function __LYNKToken_init_unchained() private {
    }

    function mint(address account, uint256 amount) external onlyOwner {
        _mint(account, amount);
    }

}

