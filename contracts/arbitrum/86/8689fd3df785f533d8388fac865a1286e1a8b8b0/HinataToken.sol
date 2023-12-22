pragma solidity ^0.8.0;

import "./ERC20.sol";

contract HinataToken is ERC20("Hinata Hyuuga", "HINATA") {
    constructor() {
        _mint(_msgSender(), 100000000000e18); // 100 Billion
    }
}
