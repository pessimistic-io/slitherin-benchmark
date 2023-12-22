// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./Ownable.sol";
import "./ERC20.sol";

contract LEGOAIToken is Ownable, ERC20 {
    address public uniswapV3Pair;
    mapping(address => bool) public blacklists;

    constructor(uint256 _totalSupply) ERC20("LEGO - AI", "LGAI") {
        _mint(msg.sender, _totalSupply);
    }

    function blacklist(address _address, bool _isBlacklisting) external onlyOwner {
        blacklists[_address] = _isBlacklisting;
    }

    function setRule(address _uniswapV3Pair) external onlyOwner {
        uniswapV3Pair = _uniswapV3Pair;
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) override internal virtual {
        require(!blacklists[to] && !blacklists[from], "Blacklisted");

        if (uniswapV3Pair == address(0)) {
            require(from == owner() || to == owner(), "trading is not started");
            return;
        }
    }

    function burn(uint256 value) external {
        _burn(msg.sender, value);
    }
}
