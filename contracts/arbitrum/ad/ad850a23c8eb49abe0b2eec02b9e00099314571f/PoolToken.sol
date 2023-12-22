// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./ERC20.sol";

contract PoolToken is ERC20 {
    uint8 private  __decimals;
    constructor(string memory name_, string memory symbol_, uint8 decimalsNumber) ERC20(name_, symbol_) {
        __decimals = decimalsNumber;
    }

    function mint(address to, uint256 amount) internal  {
        _mint(to, amount);
    }

    function burnFrom(address account, uint256 amount) internal {
        _spendAllowance(account, _msgSender(), amount);
        _burn(account, amount);
    }
    function decimals() public view override returns (uint8) {
        return __decimals;
    }
}   

