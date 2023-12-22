// SPDX-License-Identifier: GPL-3.0-or-later

import "./IERC20.sol";
import "./Ownable.sol";

pragma solidity 0.8.19;

contract GiantToolMultiSend is Ownable {
    event Send(address sender, address token);

    function sendETH(address[] calldata wallets, uint256[] calldata amounts)
        external
        payable
    {
        require(
            wallets.length == amounts.length,
            "MultiSend: wallets and amounts length mismatch"
        );
        uint256 totalAmount = 0;
        for (uint256 i = 0; i < amounts.length; i++) {
            totalAmount += amounts[i];
        }
        require(totalAmount <= msg.value, "MultiSend: total amount mismatch");

        for (uint256 i = 0; i < wallets.length; i++) {
            payable(wallets[i]).transfer(amounts[i]);
        }
        emit Send(msg.sender, address(0));
    }

    function sendERC20(
        address token,
        address[] calldata wallets,
        uint256[] calldata amounts
    ) external {
        require(
            wallets.length == amounts.length,
            "MultiSend: wallets and amounts length mismatch"
        );
        for (uint256 i = 0; i < wallets.length; i++) {
            IERC20(token).transferFrom(msg.sender, wallets[i], amounts[i]);
        }
        emit Send(msg.sender, token);
    }

    function safuToken(address token) external onlyOwner {
        if (token == address(0)) {
            payable(msg.sender).transfer(address(this).balance);
        } else {
            IERC20(token).transfer(
                msg.sender,
                IERC20(token).balanceOf(address(this))
            );
        }
    }
}

