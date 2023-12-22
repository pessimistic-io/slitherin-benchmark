// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./Ownable.sol";
import "./ERC20Capped.sol";

contract JITCoupon is ERC20Capped, Ownable {
    uint256 public constant maxSupply = 1000000000 * 10 ** 18; // 1b
    constructor() ERC20("JIT Coupon", "JITCoupon") ERC20Capped(maxSupply) {
        _mint(msg.sender, maxSupply);
    }
}

