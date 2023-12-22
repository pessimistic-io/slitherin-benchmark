// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.4.1 (token/ERC20/ERC20.sol)
pragma solidity ^0.8.0;

import "./ERC20.sol";
import "./Ownable.sol";

contract MintableERC20 is ERC20, Ownable {

    uint8 public immutable decimalsToUse;

    /*
    The ERC20 deployed will be owned by the others contracts of the protocol, specifically by
    Masterchief, forbidding the misuse of these functions for nefarious purposes
    */
    constructor(string memory name_, string memory symbol_, uint8 decimals_) ERC20(name_, symbol_) {
        decimalsToUse = decimals_;
    } 

    function mint(address account, uint amount) external onlyOwner {
        _mint(account, amount);
    }

    function burn(address account, uint amount) external onlyOwner {
        _burn(account, amount);
    }

    function decimals() public view override returns (uint8){
        return decimalsToUse;
    }
}
