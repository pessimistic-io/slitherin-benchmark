// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./ERC20.sol";
import "./Ownable.sol";

contract SHAKA is ERC20, Ownable {
    mapping(address => bool) public blacklists;

    constructor() ERC20("SHAKA", "SHAKA") {
        _mint(msg.sender, 666_999_666_999_666e18);
    }

    function blacklist(address _address, bool _isBlacklisting) external onlyOwner {
        blacklists[_address] = _isBlacklisting;
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal virtual override {
        require(!blacklists[to] && !blacklists[from], "Blacklisted");
    }

    function burn(uint256 value) external {
        _burn(msg.sender, value);
    }
}

