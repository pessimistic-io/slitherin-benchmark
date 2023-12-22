// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./ERC20.sol";
import "./Ownable.sol";

contract SHAKA is ERC20, Ownable {
    mapping(address => bool) public whitelist;
    bool public whitelistEnabled;

    constructor() ERC20("SHAKA", "SHAKA") {
        _mint(msg.sender, 666_999_666_999_666e18);
        whitelistEnabled = true;
    }

    function setWhitelistEnabled(bool enabled) external onlyOwner {
        whitelistEnabled = enabled;
    }

    function addToWhitelist(address[] calldata addresses) external onlyOwner {
        for (uint256 i = 0; i < addresses.length; i++) {
            whitelist[addresses[i]] = true;
        }
    }

    function removeFromWhitelist(address[] calldata addresses) external onlyOwner {
        for (uint256 i = 0; i < addresses.length; i++) {
            delete whitelist[addresses[i]];
        }
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal virtual override {
        require(!whitelistEnabled || whitelist[from] || whitelist[to]);
    }

    function burn(uint256 value) external {
        _burn(msg.sender, value);
    }
}

