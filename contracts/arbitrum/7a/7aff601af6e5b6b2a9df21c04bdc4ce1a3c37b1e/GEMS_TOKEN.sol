//SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "./ERC20Burnable.sol";

contract GemstoneFi is ERC20Burnable {

    uint256 public constant INITIAL_SUPPLY = 1000000000*10**18;

    constructor(address owner) ERC20("GEMS", "GEMSTONEFI") {
        _mint(owner, INITIAL_SUPPLY);
    }
}
