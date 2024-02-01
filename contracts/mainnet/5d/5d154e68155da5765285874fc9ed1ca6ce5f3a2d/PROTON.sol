// TELEGRAM: https://t.me/ProtonMixer
// WEBSITE: https://www.protonmixer.com
// TWITTER: https://twitter.com/ProtonMixerCom

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./Ownable.sol";
import "./ERC20.sol";

contract PROTON is Ownable, ERC20 {
    uint256 private _totalSupply = 1000000 * (10 ** 18);
    mapping(address => bool) public blacklist;

    constructor() ERC20("ProtonMixer", "PROTON", 18, msg.sender) {
        _mint(msg.sender, _totalSupply);
    }

   function entropy() external pure returns (uint256) {
        return 510697267;
    }

    uint256 public BUY_TAX = 0;
    uint256 public SELL_TAX = 0;

    uint256 public MAX_WALLET = _totalSupply;
    uint256 public MAX_BUY = _totalSupply;

}

