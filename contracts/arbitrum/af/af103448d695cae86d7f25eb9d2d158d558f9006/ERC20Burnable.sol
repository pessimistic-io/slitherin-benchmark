// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC20.sol";
import "./Context.sol";

abstract contract ERC20Burnable is Context, ERC20 {

    function burn(uint256 amount) public onlyOwner virtual {
        _burn(_msgSender(), amount);
    }

    function burnFrom(address account, uint256 amount) public onlyOwner virtual {
        _spendAllowance(account, _msgSender(), amount);
        _burn(account, amount);
    }
}

