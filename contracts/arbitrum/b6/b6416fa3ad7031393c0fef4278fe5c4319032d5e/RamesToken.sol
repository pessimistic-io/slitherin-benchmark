// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./ERC20.sol";
import "./ERC20Burnable.sol";
import "./Ownable.sol";

contract RamesToken is ERC20, ERC20Burnable, Ownable {
    mapping(address => bool) public whitelist;
    bool public isBootstrapping;

    constructor() ERC20("Rames Exchange", "RAM") {
        isBootstrapping = false;
        whitelist[msg.sender] = true;
    }

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }

    function transfer(address to, uint256 amount) public virtual override returns (bool) {
        address owner = _msgSender();
        if (isBootstrapping) {
            require(whitelist[owner], "TRANSFER_ERROR");
        }
        _transfer(owner, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public virtual override returns (bool) {
        address spender = _msgSender();
        _spendAllowance(from, spender, amount);
        if (isBootstrapping) {
            require(whitelist[from], "TRANSFER_ERROR");
        }
        _transfer(from, to, amount);
        return true;
    }

    function setWhitelist(address user) external onlyOwner {
        whitelist[user] = true;
    }

    function unsetWhitelist(address user) external onlyOwner {
        delete whitelist[user];
    }

    function setBootstrapStatus(bool _isBootstrapping) external onlyOwner {
        isBootstrapping = _isBootstrapping;
    }
}

