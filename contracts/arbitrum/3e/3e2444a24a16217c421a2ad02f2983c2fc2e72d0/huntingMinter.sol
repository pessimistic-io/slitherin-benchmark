// contracts/GLDToken.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC20.sol";
import "./Ownable.sol";
import "./huntingCoin.sol";

contract HuntingMinter is Ownable {
    address token;
    HuntingCoin coin;

    constructor(address _token) {
        token = _token;
        coin = HuntingCoin(_token);
    }

    function mint() public {
        
        coin.mint(msg.sender, 1000*10**18);
    }
}

