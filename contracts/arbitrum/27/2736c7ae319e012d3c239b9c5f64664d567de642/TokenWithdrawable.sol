//SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./IERC20.sol";
import "./SafeERC20.sol";
import "./Ownable.sol";

contract TokenWithdrawable is Ownable {
    using SafeERC20 for IERC20;

    /**
     * @notice Saves any tokens sent to the contract by mistake.
     */
    function withdrawToken(IERC20 token, uint amount, address to) external onlyOwner {
        token.safeTransfer(to, amount);
    }
}
