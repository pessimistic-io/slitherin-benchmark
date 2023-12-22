// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC20} from "./ERC20.sol";
import "./xUSD.sol";

contract xUSDManager {

    function depositAndMint(uint256 amount, address token) public {
        require(amount > 0, "Amount must be greater than 0");

        ERC20(token).transferFrom(msg.sender, address(this), amount);
        
        xUSD xusd = xUSD(address(this));
        mint(xusd, msg.sender, amount);
    }

    function mint(xUSD _xusd, address account, uint256 amount) public {
        _xusd.mint(account, amount);
    }
}

