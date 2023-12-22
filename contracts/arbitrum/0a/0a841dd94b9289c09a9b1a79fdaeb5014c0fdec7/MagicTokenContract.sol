// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.2;
import "./ERC20.sol";
import "./Ownable.sol";

contract MagicTokenContract is ERC20, Ownable {
    mapping(address => bool) private adminAccess;

    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {}

    function setAdminAccess(address user, bool access) external onlyOwner {
        adminAccess[user] = access;
    }

    function mint(uint256 amount, address receiver) external onlyAdminAccess {
        _mint(receiver, amount);
    }

    modifier onlyAdminAccess() {
        require(adminAccess[_msgSender()] == true || _msgSender() == owner(), "Require admin access");
        _;
    }
}

