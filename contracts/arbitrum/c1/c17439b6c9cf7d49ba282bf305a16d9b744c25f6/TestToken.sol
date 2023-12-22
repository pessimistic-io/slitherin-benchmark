// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./draft-ERC20Permit.sol";
import "./ERC20Burnable.sol";
import "./Ownable.sol";
import "./SafeERC20.sol";

contract TestToken is ERC20Burnable, ERC20Permit, Ownable {
    using SafeERC20 for IERC20;

    mapping(address => bool) public minters;

    uint256 internal constant MAX_TOTAL_SUPPLY = 100000000 ether;

    constructor() ERC20("Test Token", "TEST") ERC20Permit("TEST") {}

    function mint(address to, uint256 amount) external {
        require(minters[msg.sender], "not a minter");
        require(amount + totalSupply() <= MAX_TOTAL_SUPPLY, "max reached");
        _mint(to, amount);
    }

    function setMinter(address _minter) external onlyOwner {
        minters[_minter] = true;
    }

    function removeMinter(address _minter) external onlyOwner {
        minters[_minter] = false;
    }
}

