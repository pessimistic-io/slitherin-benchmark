// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./ERC20BulkSender.sol";

contract BadAddress2 {
    address[] recipients = [address(this)];
    uint256[] amounts = [0];

    receive() external payable {
        ERC20BulkSender(payable(msg.sender)).airdrop(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE, recipients, amounts);
    }

}
