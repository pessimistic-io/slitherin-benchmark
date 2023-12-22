// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import "./ERC20.sol";

contract MGTAI is ERC20 {
    constructor(
        string memory _name, 
        string memory _symbol, 
        uint256 _supply
    ) ERC20(_name, _symbol) {
        _mint(msg.sender, _supply);
    }

    function burn(uint256 _amount) public {
        _burn(msg.sender, _amount);
    }
}
