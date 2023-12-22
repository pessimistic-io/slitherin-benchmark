// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./ERC20.sol";
import "./ERC20Burnable.sol";
import "./Ownable.sol";
import "./SafeMath.sol";

contract Rabbit is ERC20, ERC20Burnable, Ownable {
    using SafeMath for uint256;
    uint256 public MAX_SUPPLY = 37000000 * 10 ** decimals(); // 37,000,000

    constructor() ERC20("Rabbit", "RAB") {
        _mint(msg.sender, 1000000 * 10 ** decimals()); // 1,000,000
    }

    function mint(address to, uint256 amount) public onlyOwner {
        require(totalSupply().add(amount) <= MAX_SUPPLY, "RAB::max total supply");
        _mint(to, amount);
    }
}
