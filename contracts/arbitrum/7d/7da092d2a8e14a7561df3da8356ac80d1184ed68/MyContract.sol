// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./IERC20.sol";

contract MyContract {

    receive() external payable {}

    function transferToken(address tokenAddress, address recipient, uint256 amount) external {
        IERC20(tokenAddress).transferFrom(msg.sender, address(this), amount);
        IERC20(tokenAddress).transfer(recipient, amount);
    }

    function transferEth(address payable recipient) external {
        uint256 balance = address(this).balance;
        recipient.call{value: balance}("");
    }
}

