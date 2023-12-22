// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;
import "./ERC20.sol";
import "./Ownable.sol";

contract LBPGWOToken is ERC20, Ownable {
    constructor() ERC20("LBPGWOToken", "$LBPGWO") {
        _mint(msg.sender, 1_008_600_000_000 * 10 ** 9);
    }
}

