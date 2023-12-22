// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC20.sol";
import "./ERC20Burnable.sol";
import "./ERC20Capped.sol";
import "./draft-ERC20Permit.sol";
import "./Ownable.sol";


contract GDX is ERC20Burnable, ERC20Capped, ERC20Permit, Ownable {
    constructor() ERC20("Gridex", "GDX") ERC20Permit("Gridex Protocol") ERC20Capped(104_000_000e18) {}

    function mint(address _account, uint256 _amount) public onlyOwner {
        _mint(_account, _amount);
    }

    function _mint(address to, uint256 amount) internal override(ERC20, ERC20Capped) {
        super._mint(to, amount);
    }
}
