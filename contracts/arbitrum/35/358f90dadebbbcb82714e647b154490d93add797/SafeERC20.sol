pragma solidity >=0.8.0;

import {SafeTransferLib} from "./SafeTransferLib.sol";
import {IERC20} from "./ERC20_IERC20.sol";

/**
 * wrap SafeTransferLib to retain oz SafeERC20 signature
 */
library SafeERC20 {
    function safeTransferFrom(IERC20 token, address from, address to, uint256 amount) internal {
        SafeTransferLib.safeTransferFrom(address(token), from, to, amount);
    }

    function safeTransfer(IERC20 token, address to, uint256 amount) internal {
        SafeTransferLib.safeTransfer(address(token), to, amount);
    }

    function safeIncreaseAllowance(IERC20 token, address spender, uint256 amount) internal {
        uint256 allowance = token.allowance(msg.sender, spender) + amount;
        SafeTransferLib.safeApprove(address(token), spender, allowance);
    }
}

