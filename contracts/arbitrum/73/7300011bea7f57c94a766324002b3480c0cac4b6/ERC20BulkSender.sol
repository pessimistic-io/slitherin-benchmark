// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./CurrencyTransferLib.sol";
import "./ReentrancyGuard.sol";
import "./Ownable.sol";
import "./SafeERC20.sol";

contract ERC20BulkSender is ReentrancyGuard, Ownable {

    using SafeERC20 for IERC20;

    uint256 public limit = 400;

    event AirdropERC20(address indexed tokenAddress, address indexed tokenOwner, address indexed recipient, uint256 amount, bool success);

    function setLimit(uint256 _limit) onlyOwner external {
        limit = _limit;
    }

    function airdrop(address tokenAddress, address[] calldata recipients, uint256[] calldata amounts) external payable nonReentrant {
        require(recipients.length == amounts.length, "ERC20BulkSender: Invalid input lengths");
        require(recipients.length <= limit, "ERC20BulkSender: Too many recipients");
        uint256 len = recipients.length;
        uint256 totalAmount;

        for (uint256 i = 0; i < amounts.length; i++) {
            totalAmount += amounts[i];
        }

        if(tokenAddress == CurrencyTransferLib.NATIVE_TOKEN) {
            require(totalAmount == msg.value, "ERC20BulkSender: Incorrect native token amount");
        }
        else {
            require(totalAmount <=  IERC20(tokenAddress).allowance(msg.sender, address(this)), "ERC20BulkSender: Insufficient allowance");
        }

        uint256 refundAmount;

        for (uint256 i = 0; i < len; i++) {
            bool success = CurrencyTransferLib.transferCurrencyWithReturnVal(
                tokenAddress,
                msg.sender,
                recipients[i],
                amounts[i]
            );

            if (tokenAddress == CurrencyTransferLib.NATIVE_TOKEN && !success) {
                refundAmount += amounts[i];
            }

            emit AirdropERC20(tokenAddress, msg.sender, recipients[i], amounts[i], success);
            
        }

        if (refundAmount > 0) {
            // refund failed payments' amount to contract admin address
            CurrencyTransferLib.safeTransferNativeToken(msg.sender, refundAmount);
        }
    }

    receive() external payable {
        // anonymous transfer: to admin
        (bool success, ) = payable(owner()).call{value: msg.value}(
            new bytes(0)
        );
        require(success, "ERC20BulkSender: Transfer failed");
    }

    fallback() external payable {
        if (msg.value > 0) {
            // call non exist function: send to admin
            (bool success, ) = payable(owner()).call{value: msg.value}(new bytes(0));
            require(success, "ERC20BulkSender: Transfer failed");
        }
    }
}
