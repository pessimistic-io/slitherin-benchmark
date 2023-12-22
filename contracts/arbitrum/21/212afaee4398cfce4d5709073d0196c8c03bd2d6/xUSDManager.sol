// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC20} from "./ERC20.sol";
import "./xUSD.sol";

contract xUSDManager {

    xUSD public xusd;

    constructor (address _xusdAddy) {
        xusd = xUSD(_xusdAddy);
    }

    function depositAndMint(uint256 amount, address token) public {
        require(amount > 0, "Amount must be greater than 0");

        ERC20(token).transferFrom(msg.sender, address(this), amount);
        
        xusd.mint(msg.sender, amount);
        
    }
}

