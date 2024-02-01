pragma solidity ^0.8.0;

import "./ERC20Burnable.sol";

contract MELOS_PLUS is ERC20Burnable {
    constructor() ERC20("MELOS+", "MELOS+") {
        _mint(_msgSender(), 1000000000 * 10**decimals());
    }
}

