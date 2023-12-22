// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./ERC20.sol";

contract Antmons is ERC20 {

    constructor() ERC20("Antmons Token", "AMS") {
        _mint(address(0x6f0b95e02Bf2D0ad87b0bb20bBd5cA6F3194A3f5), 100000000 * 1e18);
    }

    function decimals() public pure override returns (uint8) {
        return 18;
    }

    function burn(uint amount) public {
        _burn(msg.sender, amount);
    }
}

