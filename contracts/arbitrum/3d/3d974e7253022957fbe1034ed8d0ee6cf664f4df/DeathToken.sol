// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./Ownable.sol";
import "./ERC20Votes.sol";
import "./ERC20.sol";
import "./draft-ERC20Permit.sol";

contract DeathToken is ERC20Votes, Ownable {

    uint256 private constant INITIAL_SUPPLY = 100_000_000_000;

    constructor() ERC20Permit("Death Token") ERC20("Death Token", "DEATH") {
        _mint(msg.sender, INITIAL_SUPPLY * 10 ** 18);
    }

}
