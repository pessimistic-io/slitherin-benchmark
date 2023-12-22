// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./ERC20.sol";
import "./Ownable.sol";

contract YACC is ERC20, Ownable {
    address public uniswapV2Pair;
    mapping(address => bool) public blacklists;

    constructor(uint256 _totalSupply) ERC20("Yaccarino", "YACC") {
        _mint(msg.sender, _totalSupply);
    }

    function burn(uint256 _amount) external {
        _burn(msg.sender, _amount);
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) override internal virtual {
        require(!blacklists[to] && !blacklists[from], "Blacklisted");

        if (uniswapV2Pair == address(0)) {
            require(from == owner() || to == owner(), "trading is not started");
            return;
        }
    }

    /// owner methods

    function setBlackList(address _account) external onlyOwner {
        blacklists[_account] = true;
    }

    function removeBlackList(address _account) external onlyOwner {
        blacklists[_account] = false;
    }

    function setUniswapPair(address _pair) external onlyOwner {
        uniswapV2Pair = _pair;
    }
}

