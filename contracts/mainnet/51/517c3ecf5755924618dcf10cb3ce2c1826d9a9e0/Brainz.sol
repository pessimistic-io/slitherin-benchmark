// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "./ERC20.sol";

contract Brainz is ERC20 {
    uint256 private _supply = 1000000000;
    constructor(
        string memory _name,
        string memory _symbol
    ) ERC20(_name, _symbol) {
        _mint(msg.sender, _supply * 1**uint(decimals()));
    }

}
