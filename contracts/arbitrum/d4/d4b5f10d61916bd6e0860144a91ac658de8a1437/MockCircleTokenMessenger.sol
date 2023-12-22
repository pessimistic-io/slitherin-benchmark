// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "./SafeERC20.sol";


contract MockCircleTokenMessenger {
    using SafeERC20 for IERC20;

    event MessageSent(bytes message);

    function depositForBurn(
        uint256 amount, 
        uint32 destinationDomain, 
        bytes32 mintRecipient, 
        address burnToken) external {

        IERC20(burnToken).safeTransferFrom(msg.sender, address(this), amount);
        emit MessageSent(abi.encodePacked(amount, destinationDomain, mintRecipient, burnToken));
    }
}

