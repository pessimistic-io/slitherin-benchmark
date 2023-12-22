// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./Ownable.sol";
import "./ERC20Burnable.sol";

contract GoodGameGuildToken is Ownable, ERC20Burnable {
    constructor(address wallet, uint256 _totalSupply) Ownable() ERC20("Good Games Guild", "GGG") {
        _mint(wallet, _totalSupply);
        transferOwnership(wallet);
    }
}
