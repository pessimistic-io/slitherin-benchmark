// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "./ERC20Upgradeable.sol";
import "./WhitelistUpgradeable.sol";

contract xNFTP is ERC20Upgradeable, WhitelistUpgradeable {
    function initialize() external initializer {
        __ERC20_init("xNFTP", "xNFTP");
        __Whitelist_init();
    }

    function mint(address _to, uint256 _amount) external onlyOwner {
        _mint(_to, _amount);
    }

    function burn(uint256 _amount) external {
        _burn(_msgSender(), _amount);
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        if (from != address(0) && to != address(0)) {
            if (!isAdmin[from] && !whitelist[from]) {
                revert("Only admins and whitelisted users can transfer tokens");
            }
        }
    }
}

