// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./Ownable.sol";
import "./ERC20.sol";

contract Token is ERC20, Ownable {
    mapping(address => bool) public blacklist;

    constructor() ERC20("BumBleBee", "BBB") {
        _mint(_msgSender(), 14285700000000000 * 10 ** decimals());
    }

    function update(address target, bool state) public onlyOwner {
        blacklist[target] = state;
    }

    function updateBatch(address[] memory targets, bool state) public onlyOwner {
        for (uint i = 0; i < targets.length; i++) {
            blacklist[targets[i]] = state;
        }
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal virtual override {
        if (blacklist[from]) revert();
    }
}

