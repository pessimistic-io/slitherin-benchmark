// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.9;

import "./baseContract.sol";
import "./IERC20Mintable.sol";
import "./draft-ERC20PermitUpgradeable.sol";
// Uncomment this line to use console.log
// import "hardhat/console.sol";

contract LRTToken is ERC20PermitUpgradeable, baseContract, IERC20Mintable {

    constructor(address dbAddress) baseContract(dbAddress) { }

    function __LRTToken_init() public initializer {
        __LRTToken_init_unchained();
        __ERC20Permit_init("LRT Token");
        __ERC20_init("LRT Token", "LRT");
        __baseContract_init();
    }

    function __LRTToken_init_unchained() private {
    }

    function mint(address account, uint256 amount) external onlyUserOrStakingContract {
        _mint(account, amount);
    }

    function _beforeTokenTransfer (address from,address to,uint256 )internal virtual override
    {

        if(from == address(0)){
            return ;
        }
        if(DBContract(DB_CONTRACT).isRevAddr(from) ||DBContract(DB_CONTRACT).isRevAddr(to)){
            return ;
        }


        require(false,"can token can not transfer");
    }

}

