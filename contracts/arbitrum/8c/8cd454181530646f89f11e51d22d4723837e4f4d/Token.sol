// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {ERC20} from "./ERC20.sol";
import {Owned} from "./Owned.sol";

contract RewardToken is ERC20, Owned {

    constructor() ERC20("Reward Token", "RWD", 18) Owned(msg.sender) {}

    function mint(uint256 amount) external onlyOwner {
        _mint(msg.sender, amount);
    }

    function setName(string memory _name, string memory _symbol) external onlyOwner {
        name = _name;
        symbol = _symbol;
    }
}


