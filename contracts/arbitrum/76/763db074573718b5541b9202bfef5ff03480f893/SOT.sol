pragma solidity ^0.8.0;

import "./ERC20.sol";

contract SOT is ERC20("Show Off Token", "SOT") {
    constructor() {
        _mint(_msgSender(), 1000000000000e18); // 1 Trillion
    }
}
