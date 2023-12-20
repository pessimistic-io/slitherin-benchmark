// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;
//community token since these virgins keep on timerugging
import "./ERC20.sol";
import "./Ownable.sol";

contract POOToken is ERC20, Ownable {
    constructor() ERC20("POO Token", "POO") {
        _mint(msg.sender, 8000000000000 * 10 ** decimals());
    }
}

