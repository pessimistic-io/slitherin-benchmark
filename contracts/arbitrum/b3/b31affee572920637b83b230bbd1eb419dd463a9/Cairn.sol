// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0 <=0.8.19;

import "./IFlashLoanRecipient.sol";
import "./IVault.sol";
import "./IMauser.sol";
import "./MauserFlashLoanProvider.sol";

contract Cairn is MauserFlashLoanProvider, IFlashLoanRecipient {
    IVault private constant VAULT = IVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
    bool private sentinel = false;

    constructor(IMauser mauser) MauserFlashLoanProvider(mauser) {}

    function receiveFlashLoan(
        IERC20[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory userData
    ) public override {
        require(sentinel && msg.sender == address(VAULT));
        IERC20 token = tokens[0];
        uint256 amount = amounts[0];
        uint256 fee = feeAmounts[0];
        multiSend(userData);
        uint256 balance = IERC20(token).balanceOf(address(this));
        uint256 deducted = amount + fee;
        require(balance >= deducted);
        token.transfer(address(MAUSER), balance - deducted);
        token.transfer(address(VAULT), deducted);
    }

    function mauserFlashLoanAndMultiSend(address token, uint256 amount, bytes memory transactions) public payable {
        IERC20[] memory tokens = new IERC20[](1);
        uint256[] memory amounts = new uint256[](1);
        tokens[0] = IERC20(token);
        amounts[0] = amount;
        sentinel = true;
        VAULT.flashLoan(this, tokens, amounts, transactions);
        sentinel = false;
    }
}

