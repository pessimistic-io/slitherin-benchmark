// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./ERC20.sol";

contract REEE is ERC20 {
    uint private constant _numTokens = 1_000_000_000_000_000;

    constructor() {
        _mint(msg.sender, _numTokens * (10 ** 18));
    }

    function name() public view virtual override returns (string memory) {
        return "REEEEEEEEEEEEE";
    }

    function symbol() public view virtual override returns (string memory) {
        return "REEE";
    }

    function burn(uint256 amount) public {
        _burn(msg.sender, amount);
    }
}

