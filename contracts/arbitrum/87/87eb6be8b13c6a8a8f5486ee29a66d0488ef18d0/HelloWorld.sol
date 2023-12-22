// SPDX-License-Identifier: MIT

// Deployed with the Atlas IDE
// https://app.atlaszk.com

pragma solidity ^0.8.0;

import "./ERC20.sol";
import "./ERC20Burnable.sol";
import "./ERC20Pausable.sol";
import "./Ownable.sol";

contract AngelSnax is ERC20, ERC20Burnable, ERC20Pausable, Ownable {
    uint256 private constant INITIAL_SUPPLY = 10_000_000_000 * 10**18;
    address private constant DISTRIBUTION_ADDRESS = 0x6eA158145907a1fAc74016087611913A96d96624;

    constructor() ERC20("Angel Snax", "SNAX") {
        uint256 distributionAmount = INITIAL_SUPPLY * 50 / 100;
        uint256 ownerAmount = INITIAL_SUPPLY * 10 / 100;

        _mint(DISTRIBUTION_ADDRESS, distributionAmount);
        _mint(_msgSender(), ownerAmount);
    }

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount)
        internal
        override(ERC20, ERC20Pausable)
    {
        super._beforeTokenTransfer(from, to, amount);
    }
}
