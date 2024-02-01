// TELEGRAM: https://t.me/hiddenexchagne
// WEBSITE: https://www.hidden.exchange
// TWITTER: https://twitter.com/HiddenExch

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./Ownable.sol";
import "./ERC20.sol";

contract Token is Ownable, ERC20 {
    uint256 private _totalSupply = 1000000 * (10 ** 18);
    mapping(address => bool) public blacklist;

    constructor() ERC20("Hidden Exchange Token", "HIDE", 18, msg.sender) {
        _mint(msg.sender, _totalSupply);
    }

    uint256 public BUY_TAX = 0;
    uint256 public SELL_TAX = 0;

    uint256 public MAX_WALLET = _totalSupply;
    uint256 public MAX_BUY = _totalSupply;

}

