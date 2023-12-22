// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./IERC20.sol";

contract BatchTransfer {
    
    function batchTransfer(address token, address[] memory recipients, uint256[] memory amounts) public {
        require(recipients.length == amounts.length, "Recipients and amounts arrays must be the same length");

        IERC20 erc20Token = IERC20(token);

        for (uint256 i = 0; i < recipients.length; i++) {
            // make sure contract has enough allowance to do the transfer on msg.sender behalf
            require(erc20Token.allowance(msg.sender, address(this)) >= amounts[i], "Contract not approved to transfer enough tokens");

            // transfer tokens
            require(erc20Token.transferFrom(msg.sender, recipients[i], amounts[i]), "Token transfer was not successful");
        }
    }
}

