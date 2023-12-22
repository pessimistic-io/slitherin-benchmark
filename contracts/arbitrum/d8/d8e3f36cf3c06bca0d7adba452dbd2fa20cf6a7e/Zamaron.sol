// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC20.sol";
import "./Ownable.sol";

contract Zamaron is ERC20, Ownable {
    constructor() ERC20("Zamaron", "ZMR") {
        uint256 totalSupply = 1_000_000_000_000 * 10 ** decimals();
        _mint(msg.sender, totalSupply);
    }

    // Function to allow the token owner to burn tokens
    function burnTokens(uint256 amount) public onlyOwner {
        _burn(msg.sender, amount);
    }

    // Function to transfer ownership to a new address
    function transferTokenOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "Invalid address");
        transferOwnership(newOwner);
    }
}

