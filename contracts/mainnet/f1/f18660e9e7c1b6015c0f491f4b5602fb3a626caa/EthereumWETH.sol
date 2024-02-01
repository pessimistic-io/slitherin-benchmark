// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./ERC20.sol";
import "./access_Ownable.sol";

contract EthereumWETH is ERC20, Ownable {
    constructor() ERC20("EthereumWETH", "EWETH") {}

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }
}

