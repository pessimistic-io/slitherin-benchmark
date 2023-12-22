// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import "./tokens_ERC20.sol";
import "./Owned.sol";

contract ERC20Main is ERC20, Owned {

    constructor(
        string memory _name,
        string memory _symbol,
        uint _maxSupply
    ) ERC20(_name, _symbol, 18) Owned(msg.sender) {
        _mint(msg.sender, _maxSupply * 1e18);
    }
}


