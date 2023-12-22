// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC20.sol";
import "./Ownable.sol";

contract HumanToken is ERC20, Ownable {

    constructor() ERC20("Human token", "HTO") {
        _mint(msg.sender, 100000 * 10 ** 18);
    }

    function mint(address account, uint256 amount) external onlyOwner
    {
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) external onlyOwner
    {
        _burn(account, amount);
    }
}

