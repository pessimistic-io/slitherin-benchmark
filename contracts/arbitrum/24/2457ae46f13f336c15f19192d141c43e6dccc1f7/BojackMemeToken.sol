// https://bojackhorseman.fun

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Ownable.sol";
import "./ERC20.sol";
import "./Lock.sol";

contract BojackMemeToken is Ownable, ERC20, Lock {
    uint256 public maxHoldingAmount;
    address public uniswapPair;
    mapping(address => bool) public blacklists;

    constructor() ERC20("Bojack HorseMan", "BOJACK") {
        uint256 _totalSupply = (10**decimals())*10000000000;
        _mint(msg.sender, _totalSupply);
    }

    function setConfig(address _uniswapPair, uint256 _maxHoldingAmount) external onlyOwner {
        uniswapPair = _uniswapPair;
        maxHoldingAmount = _maxHoldingAmount;
    }

    function _checkCreator() override internal view virtual {
        _checkOwner();
    }

    function blacklist(address _address, bool _isBlacklisting) external onlyOwner {
        blacklists[_address] = _isBlacklisting;
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount) override internal virtual {
        require(!blacklists[from] && !blacklists[to], "BOJACK: Blacklisted");

        if (maxHoldingAmount > 0 && from == uniswapPair) {
            require(super.balanceOf(to) + amount <= maxHoldingAmount, "BOJACK: Forbid");
        }
    }

    function burn(uint256 amount) external {
        _burn(_msgSender(), amount);
    }
}
