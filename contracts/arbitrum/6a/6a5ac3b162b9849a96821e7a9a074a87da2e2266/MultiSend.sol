// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./Ownable.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";

contract MultiSend is Ownable {
    using SafeERC20 for IERC20;

    uint256 constant public maxPerCall = 1000;

    error IncorrectArrLen();
    error ToMuchAddresses();

    receive() external payable {}

    function sendErc20(IERC20 token, address[] calldata addresses, uint256[] calldata amounts) external onlyOwner {
        if (addresses.length != amounts.length) {
            revert IncorrectArrLen();
        }

        if (addresses.length > maxPerCall) {
            revert ToMuchAddresses();
        }

        for (uint256 i = 0; i < addresses.length;) {
            token.safeTransfer(addresses[i], amounts[i]);

            unchecked {
                ++i;
            }
        }
    }

    function sendNative(address payable[] calldata addresses, uint256[] calldata amounts) external onlyOwner {
        if (addresses.length != amounts.length) {
            revert IncorrectArrLen();
        }

        if (addresses.length > maxPerCall) {
            revert ToMuchAddresses();
        }

        for (uint256 i = 0; i < addresses.length;) {
            addresses[i].transfer( amounts[i]);

            unchecked {
                ++i;
            }
        }
    }

    function withdrawToken(IERC20 token, uint256 amount) external onlyOwner {
        token.safeTransfer(msg.sender, amount);
    }

    function withdrawNative(uint256 amount) external onlyOwner {
        payable(msg.sender).transfer(amount);
    }
}

