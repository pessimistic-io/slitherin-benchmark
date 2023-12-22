//SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "./SafeERC20.sol";
import "./IERC20.sol";

library UniversalERC20 {
    using SafeERC20 for IERC20;

    IERC20 internal constant ZERO_ADDRESS =
        IERC20(0x0000000000000000000000000000000000000000);
    IERC20 internal constant ETH_ADDRESS =
        IERC20(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

    function universalTransfer(
        IERC20 token,
        address to,
        uint256 amount
    ) internal {
        if (amount == 0) {
            return;
        }

        if (isETH(token)) {
            (bool sent, ) = payable(address(uint160(to))).call{value: amount}(
                ""
            );
            require(sent, "Send ETH failed");
        } else {
            token.safeTransfer(to, amount);
        }
    }

    function universalTransferFrom(
        IERC20 token,
        address from,
        address to,
        uint256 amount
    ) internal {
        if (amount == 0) {
            return;
        }

        if (isETH(token)) {
            require(
                from == msg.sender && msg.value >= amount,
                "Wrong usage of ETH.universalTransferFrom"
            );
            if (to != address(this)) {
                (bool sent, ) = payable(address(uint160(to))).call{
                    value: amount
                }("");
                require(sent, "Send ETH failed");
            }
            if (msg.value > amount) {
                // refund redundant amount
                (bool sent, ) = payable(msg.sender).call{
                    value: msg.value - amount
                }("");
                require(sent, "Send-back ETH failed");
            }
        } else {
            token.safeTransferFrom(from, to, amount);
        }
    }

    function universalTransferFromSenderToThis(IERC20 token, uint256 amount)
        internal
    {
        if (amount == 0) {
            return;
        }

        if (isETH(token)) {
            require(
                msg.value >= amount,
                "Wrong usage of ETH.universalTransferFromSenderToThis"
            );
            if (msg.value > amount) {
                // Return remainder if exist
                (bool sent, ) = payable(msg.sender).call{
                    value: msg.value - amount
                }("");
                require(sent, "Send-back ETH failed");
            }
        } else {
            token.safeTransferFrom(msg.sender, address(this), amount);
        }
    }

    function universalApprove(
        IERC20 token,
        address to,
        uint256 amount
    ) internal {
        if (!isETH(token)) {
            if (amount > 0 && token.allowance(address(this), to) > 0) {
                token.safeApprove(to, 0);
            }
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

    function universalDecimals(IERC20 token) internal view returns (uint256) {
        if (isETH(token)) {
            return 18;
        }

        (bool success, bytes memory data) = address(token).staticcall{
            gas: 10000
        }(abi.encodeWithSignature("decimals()"));
        if (!success || data.length == 0) {
            (success, data) = address(token).staticcall{gas: 10000}(
                abi.encodeWithSignature("DECIMALS()")
            );
        }

        return (success && data.length > 0) ? abi.decode(data, (uint256)) : 18;
    }

    function isETH(IERC20 token) internal pure returns (bool) {
        return (address(token) == address(ZERO_ADDRESS) ||
            address(token) == address(ETH_ADDRESS));
    }
}

