pragma solidity 0.8.15;
// SPDX-License-Identifier: MIT
import "./ERC20.sol";
import "./SafeMath.sol";
import "./Ownable.sol";

contract NarwhalToken is ERC20 {
    constructor() ERC20("Narwhal Token", "NAR") {
        _mint(msg.sender, 80000000e18);
    }
}

