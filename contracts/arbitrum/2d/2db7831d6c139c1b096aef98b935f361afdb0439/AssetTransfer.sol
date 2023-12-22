// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./IERC20.sol";

library AssetTransfer {
    function cost(address from, address to, address coin, uint256 amount) internal{
        if(amount == 0 ){
            return;
        }
        if(coin == address(0)){
            require(msg.value >= amount, "The ether value sent is not correct");
            payable(to).transfer(msg.value);//retransfer to receiver
        }else{
            IERC20(coin).transferFrom(from, to, amount);
        }
    }

    function reward(address from, address to, address coin, uint256 amount) internal{
        if(amount == 0 ){
            return;
        }
        if(coin == address(0)){
            require(from.balance >= amount,"ETH balance is not enough");
            payable(to).transfer(amount);
        }else{
            IERC20(coin).transfer(to, amount);
        }
    }
}

