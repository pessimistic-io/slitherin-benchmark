// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./ERC20.sol";
import "./Owned.sol";

contract SO3 is ERC20, Owned {
    address public master;

    constructor() ERC20("SO3", "SO3", 18) Owned(msg.sender) {}

    function mint(address to, uint256 amount) external {
        require(master == msg.sender, "REJ");
        _mint(to, amount);
    }

    function setMaster(address acct) external onlyOwner {
        require(acct != address(0), "EMPTY");
        master = acct;
    }

    function resign() external {
        require(master == msg.sender, "REJ");
        master = address(0);
    }
}

