// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./ERC20.sol";
import "./Ownable.sol";
import "./console.sol";

contract Token is ERC20, Ownable {
    constructor(string memory _name, string memory _symbol, uint256 _supply) ERC20(_name, _symbol) {
        _mint(_msgSender(), _supply * 1e18);
    }

}
