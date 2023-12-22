// SPDX-License-Identifier: UNLICENSE
pragma solidity ^0.8.19;

import "./ERC20.sol";

contract DMTPokerChips is ERC20 {
    address private _contractAddress;

    constructor() ERC20("DMT Poker Chips", "DMTPC") {
        _contractAddress = address(this);
    }

    function mint(address to, uint256 amount) internal {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) internal {
        _burn(from, amount);
    }

    // solhint-disable-next-line
    function transfer(address, uint256) public override returns (bool) {
        revert("Transfers are not allowed");
    }

    // solhint-disable-next-line
    function transferFrom(address, address, uint256) public override returns (bool) {
        revert("Transfers are not allowed");
    }
}

