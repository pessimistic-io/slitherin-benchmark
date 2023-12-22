// contracts/GLDToken.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC20.sol";
import "./Ownable.sol";
import "./huntingCoin.sol";

contract HuntingBurner is Ownable {
    address token;
    HuntingCoin coin;

    constructor(address _token) {
        token = _token;
        coin = HuntingCoin(_token);
    }

    function burn(uint256 amount) public {
        
        require(coin.balanceOf(msg.sender) >= amount, "Not enough coins to burn");
        coin.transferFrom(msg.sender, address(0x000000000000000000000000000000000000dEaD),amount);
    }
}

