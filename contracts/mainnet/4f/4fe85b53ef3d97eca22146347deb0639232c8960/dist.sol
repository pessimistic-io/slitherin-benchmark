// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "./IERC20.sol";


contract disperse {
    function disperseEther(address[] memory recipients, uint256[] memory values) external payable {
        for (uint256 i = 0; i < recipients.length; i++)
            payable(recipients[i]).transfer(values[i]);
        uint256 balance = address(this).balance;
        if (balance > 0)
            payable(msg.sender).transfer(balance);
    }

    function disperseToken(IERC20 token, address[] memory recipients, uint256[] memory values) external {
        uint256 total = 0;
        for (uint256 i = 0; i < recipients.length; i++)
            total += values[i];
        require(token.transferFrom(msg.sender, address(this), total));
        for (uint64 i = 0; i < recipients.length; i++)
            require(token.transfer(recipients[i], values[i]));
    }

    function disperseTokenSameValue(IERC20 token, address[] memory recipients, uint256 value) external {
        uint256 total = recipients.length * (value * 10 ** uint(18));
        require(token.transferFrom(msg.sender, address(this), total));
        for (uint64 i = 0; i < recipients.length; i++)
            require(token.transfer(recipients[i], value));
    }

    function disperseTokenSimple(IERC20 token, address[] memory recipients, uint256[] memory values) external {
        for (uint256 i = 0; i < recipients.length; i++)
            require(token.transferFrom(msg.sender, recipients[i], values[i]));
    }

    function disperseTokenSimpleSameValue(IERC20 token, address[] memory recipients, uint256 value) external {
        for (uint256 i = 0; i < recipients.length; i++)
            require(token.transferFrom(msg.sender, recipients[i], value));
    }
}
