// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./ERC20.sol";

contract MyToken is ERC20 {
    constructor(string memory tokenName, string memory tokenSymbel, uint256 tokenAmount) ERC20(tokenName, tokenSymbel) {
        _mint(msg.sender, tokenAmount * 10 ** decimals());
    }

    function decimals() public view virtual override returns (uint8) {
        return 18;
    }
}

