// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC20.sol";

contract PlazaDAOERC20 is ERC20 {

    constructor(address to, uint256 initSupply) ERC20("plazaDAO", "plaz") {
        _mint(to, initSupply);
    }

    function burn(uint256 amount) public returns (bool) {
        _burn(_msgSender(), amount);
        return true;
    }

}

