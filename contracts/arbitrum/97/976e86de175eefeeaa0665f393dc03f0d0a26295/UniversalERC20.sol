// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "./IERC20.sol";
import "./SafeERC20.sol";

library UniversalERC20 {
    using SafeERC20 for IERC20;

    address private constant ETH_ADDRESS =
        address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

    function universalTransfer(
        IERC20 token,
        address to,
        uint256 amount
    ) internal {
        if (amount == 0) {
            return;
        }
        if (isETH(token)) {
            (bool success, ) = to.call{value: amount}("");
            require(success, "eth transfer failed");
        } else {
            token.safeTransfer(to, amount);
        }
    }

    function universalTransferFrom(
        IERC20 token,
        address from,
        uint256 amount
    ) internal {
        if (amount == 0) {
            return;
        }

        if (isETH(token)) {
            require(
                from == msg.sender && msg.value == amount,
                "Wrong useage of ETH.universalTransferFrom()"
            );
        } else {
            token.safeTransferFrom(from, address(this), amount);
        }
    }

    function universalApprove(
        IERC20 token,
        address to,
        uint256 amount
    ) internal {
        if (!isETH(token)) {
            token.safeApprove(to, amount);
        }
    }

    function universalBalanceOf(IERC20 token, address who)
        internal
        view
        returns (uint256)
    {
        if (isETH(token)) {
            return who.balance;
        } else {
            return token.balanceOf(who);
        }
    }

    function isETH(IERC20 token) internal pure returns (bool) {
        return address(token) == address(ETH_ADDRESS);
    }
}

