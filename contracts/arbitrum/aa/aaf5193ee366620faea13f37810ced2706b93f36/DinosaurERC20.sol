// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "./ERC20.sol";
import "./draft-ERC20Permit.sol";

contract DinosaurERC20 is ERC20('Dinosaur Token', 'DINO'), ERC20Permit('Dinosaur Token') {
    constructor(address _receipient, uint256 _totalSupply) {
        _mint(_receipient, _totalSupply);
    }
}
